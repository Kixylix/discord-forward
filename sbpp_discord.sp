#pragma semicolon 1

#define PLUGIN_AUTHOR "RumbleFrog, SourceBans++ Dev Team"
#define PLUGIN_VERSION "1.2.0"

#include <sourcemod>
#include <sourcebanspp>
#include <sourcecomms>
#include <SteamWorks>
#include <jansson>

#pragma newdecls required

enum
{
	Ban,
	Report,
	Comms,
	Type_Count,
	Type_Unknown,
};

int EmbedColors[Type_Count] = {
	0xDA1D87, // Ban
	0xF9D942, // Report
	0x4362FA, // Comms
};

ConVar Convars[Type_Count],
	Username,
	ProfilePictureURL,
	WebsiteBaseURL,
	DiscordRoleID;

char sEndpoints[Type_Count][256]
	, sHostname[64]
	, sHost[64]
	, sDiscordRoleID[32];

public Plugin myinfo =
{
	name = "SourceBans++ Discord Plugin",
	author = PLUGIN_AUTHOR,
	description = "Listens for ban & report forward and sends it to webhook endpoints",
	version = PLUGIN_VERSION,
	url = "https://sbpp.github.io"
};

public void OnPluginStart()
{
	CreateConVar("sbpp_discord_version", PLUGIN_VERSION, "SBPP Discord Version.", FCVAR_REPLICATED | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);

	Convars[Ban] = CreateConVar("sbpp_discord_banhook", "", "Discord web hook endpoint for ban forward. Leave empty to disable.", FCVAR_PROTECTED);
	
	Convars[Report] = CreateConVar("sbpp_discord_reporthook", "", "Discord web hook endpoint for report forward. Leave empty to disable.", FCVAR_PROTECTED);
	
	Convars[Comms] = CreateConVar("sbpp_discord_commshook", "", "Discord web hook endpoint for comms forward. Leave empty to disable.", FCVAR_PROTECTED);

	WebsiteBaseURL = CreateConVar("sbpp_website_url", "", "The base url of your website. Leave empty to disable.");

	Username = CreateConVar("sbpp_discord_username", "Sourcebans++", "The username of the webhook.");

	ProfilePictureURL = CreateConVar("sbpp_discord_pp_url", "https://sbpp.github.io/img/favicons/android-chrome-512x512.png", "A URL pointing to the profile picture for the webhook.");

	DiscordRoleID = CreateConVar("sbpp_discord_roleid", "", "The Discord role id that you would like mentioned when receiving a report. Leave empty to disable.");

	AutoExecConfig(true,"sbpp_discord");

	Convars[Ban].AddChangeHook(OnConvarChanged);
	Convars[Report].AddChangeHook(OnConvarChanged);
	Convars[Comms].AddChangeHook(OnConvarChanged);
	DiscordRoleID.AddChangeHook(OnConvarChanged);
}

/*
 * Forward declarations
 */
forward void OnConvarChanged(
	ConVar convar,
	const char[] oldValue,
	const char[] newValue
);

forward void OnHTTPRequestComplete(
	Handle hRequest,
	bool bFailure,
	bool bRequestSuccessful,
	EHTTPStatusCode eStatusCode,
	int iClient,
	int iTarget
);

forward int GetEmbedColor(int iType);

forward void GetEndpoint(
	char[] sBuffer,
	int iBufferSize,
	int iType
);

forward void GetCommType(
	char[] sBuffer,
	int iBufferSize,
	int iType
);


/*
 * Configuration initialization
 */
public void OnConfigsExecuted()
{
	FindConVar("hostname").GetString(
		sHostname,
		sizeof(sHostname)
	);

	int ip[4];

	if (SteamWorks_GetPublicIP(ip))
	{
		Format(
			sHost,
			sizeof(sHost),
			"%d.%d.%d.%d:%d",
			ip[0],
			ip[1],
			ip[2],
			ip[3],
			FindConVar("hostport").IntValue
		);
	}
	else
	{
		int iIPB = FindConVar("hostip").IntValue;

		Format(
			sHost,
			sizeof(sHost),
			"%d.%d.%d.%d:%d",
			(iIPB >> 24) & 0xFF,
			(iIPB >> 16) & 0xFF,
			(iIPB >> 8) & 0xFF,
			iIPB & 0xFF,
			FindConVar("hostport").IntValue
		);
	}

	Convars[Ban].GetString(
		sEndpoints[Ban],
		sizeof(sEndpoints[])
	);

	Convars[Report].GetString(
		sEndpoints[Report],
		sizeof(sEndpoints[])
	);

	Convars[Comms].GetString(
		sEndpoints[Comms],
		sizeof(sEndpoints[])
	);

	DiscordRoleID.GetString(
		sDiscordRoleID,
		sizeof(sDiscordRoleID)
	);
}


/*
 * SourceBans++ callbacks
 */
public void SBPP_OnBanPlayer(
	int iAdmin,
	int iTarget,
	int iTime,
	const char[] sReason
)
{
	if (sEndpoints[Ban][0] != '\0')
	{
		SendReport(
			iAdmin,
			iTarget,
			sReason,
			Ban,
			iTime
		);
	}
}

public void SourceComms_OnBlockAdded(
	int iAdmin,
	int iTarget,
	int iTime,
	int iCommType,
	char[] sReason
)
{
	if (sEndpoints[Comms][0] != '\0')
	{
		SendReport(
			iAdmin,
			iTarget,
			sReason,
			Comms,
			iTime,
			iCommType
		);
	}
}

public void SBPP_OnReportPlayer(
	int iReporter,
	int iTarget,
	const char[] sReason
)
{
	if (sEndpoints[Report][0] != '\0')
	{
		SendReport(
			iReporter,
			iTarget,
			sReason,
			Report
		);
	}
}


/*
 * Creates and sends the Discord webhook request.
 */
void SendReport(
	int iClient,
	int iTarget,
	const char[] sReason,
	int iType = Ban,
	int iTime = -1,
	any extra = 0
)
{
	/*
	 * The target is used below, so it must be a valid client.
	 */
	if (!IsValidClient(iTarget))
		return;

	char sAuthor[MAX_NAME_LENGTH];
	char sTarget[MAX_NAME_LENGTH];

	char sAuthorID[32];
	char sTargetID64[32];
	char sTargetID[32];

	char sJson[8192];
	char sBuffer[512];

	char szUsername[128];
	char szProfilePictureURL[256];
	char szWebsiteBaseURL[512];

	GetConVarString(
		ProfilePictureURL,
		szProfilePictureURL,
		sizeof(szProfilePictureURL)
	);

	GetConVarString(
		Username,
		szUsername,
		sizeof(szUsername)
	);

	GetConVarString(
		WebsiteBaseURL,
		szWebsiteBaseURL,
		sizeof(szWebsiteBaseURL)
	);

	if (IsValidClient(iClient))
	{
		GetClientName(
			iClient,
			sAuthor,
			sizeof(sAuthor)
		);

		GetClientAuthId(
			iClient,
			AuthId_Steam2,
			sAuthorID,
			sizeof(sAuthorID)
		);
	}
	else
	{
		strcopy(
			sAuthor,
			sizeof(sAuthor),
			"Console"
		);

		strcopy(
			sAuthorID,
			sizeof(sAuthorID),
			"N/A"
		);
	}

	GetClientName(
		iTarget,
		sTarget,
		sizeof(sTarget)
	);

	GetClientAuthId(
		iTarget,
		AuthId_SteamID64,
		sTargetID64,
		sizeof(sTargetID64)
	);

	GetClientAuthId(
		iTarget,
		AuthId_Steam2,
		sTargetID,
		sizeof(sTargetID)
	);

	/*
	 * Root request object:
	 *
	 * {
	 *     "username": "...",
	 *     "avatar_url": "...",
	 *     "content": "...",
	 *     "embeds": [...]
	 * }
	 */
	JsonObject jRequest =
		view_as<JsonObject>(new Json("{}"));

	JsonArray jEmbeds =
		view_as<JsonArray>(new Json("[]"));

	JsonObject jEmbed =
		view_as<JsonObject>(new Json("{}"));

	jEmbed.SetInt(
		"color",
		GetEmbedColor(iType)
	);

	/*
	 * Optional report role mention.
	 */
	if (
		iType == Report &&
		sDiscordRoleID[0] != '\0'
	)
	{
		Format(
			sBuffer,
			sizeof(sBuffer),
			"<@&%s>",
			sDiscordRoleID
		);

		jRequest.SetString(
			"content",
			sBuffer
		);
	}

	/*
	 * SourceBans website link.
	 */
	if (szWebsiteBaseURL[0] != '\0')
	{
		jEmbed.SetString(
			"title",
			"View on Sourcebans"
		);

		if (iType == Comms)
		{
			Format(
				sBuffer,
				sizeof(sBuffer),
				"%s/index.php?p=commslist&searchText=%s",
				szWebsiteBaseURL,
				sTargetID
			);
		}
		else if (iType == Ban)
		{
			Format(
				sBuffer,
				sizeof(sBuffer),
				"%s/index.php?p=banlist&searchText=%s",
				szWebsiteBaseURL,
				sTargetID
			);
		}
		else if (iType == Report)
		{
			Format(
				sBuffer,
				sizeof(sBuffer),
				"%s/index.php?p=admin&c=bans#^2",
				szWebsiteBaseURL
			);
		}

		jEmbed.SetString(
			"url",
			sBuffer
		);
	}

	/*
	 * Embed author.
	 */
	JsonObject jContentAuthor =
		view_as<JsonObject>(new Json("{}"));

	jContentAuthor.SetString(
		"name",
		sTarget
	);

	Format(
		sBuffer,
		sizeof(sBuffer),
		"https://steamcommunity.com/profiles/%s",
		sTargetID64
	);

	jContentAuthor.SetString(
		"url",
		sBuffer
	);

	jContentAuthor.SetString(
		"icon_url",
		szProfilePictureURL
	);

	jEmbed.Set(
		"author",
		jContentAuthor
	);

	/*
	 * Embed footer.
	 */
	JsonObject jContentFooter =
		view_as<JsonObject>(new Json("{}"));

	Format(
		sBuffer,
		sizeof(sBuffer),
		"%s (%s)",
		sHostname,
		sHost
	);

	jContentFooter.SetString(
		"text",
		sBuffer
	);

	jContentFooter.SetString(
		"icon_url",
		szProfilePictureURL
	);

	jEmbed.Set(
		"footer",
		jContentFooter
	);

	/*
	 * Embed fields.
	 */
	JsonArray jFields =
		view_as<JsonArray>(new Json("[]"));

	/*
	 * Author field.
	 */
	JsonObject jFieldAuthor =
		view_as<JsonObject>(new Json("{}"));

	jFieldAuthor.SetString(
		"name",
		"Author"
	);

	Format(
		sBuffer,
		sizeof(sBuffer),
		"%s (%s)",
		sAuthor,
		sAuthorID
	);

	jFieldAuthor.SetString(
		"value",
		sBuffer
	);

	jFieldAuthor.SetBool(
		"inline",
		true
	);

	jFields.Push(
		jFieldAuthor
	);

	/*
	 * Target field.
	 */
	JsonObject jFieldTarget =
		view_as<JsonObject>(new Json("{}"));

	jFieldTarget.SetString(
		"name",
		"Target"
	);

	Format(
		sBuffer,
		sizeof(sBuffer),
		"%s (%s)",
		sTarget,
		sTargetID
	);

	jFieldTarget.SetString(
		"value",
		sBuffer
	);

	jFieldTarget.SetBool(
		"inline",
		true
	);

	jFields.Push(
		jFieldTarget
	);

	/*
	 * Duration field.
	 */
	if (
		iType == Ban ||
		iType == Comms
	)
	{
		JsonObject jFieldDuration =
			view_as<JsonObject>(new Json("{}"));

		jFieldDuration.SetString(
			"name",
			"Duration"
		);

		if (iTime > 0)
		{
			Format(
				sBuffer,
				sizeof(sBuffer),
				"%d Minutes",
				iTime
			);
		}
		else if (iTime < 0)
		{
			strcopy(
				sBuffer,
				sizeof(sBuffer),
				"Session"
			);
		}
		else
		{
			strcopy(
				sBuffer,
				sizeof(sBuffer),
				"Permanent"
			);
		}

		jFieldDuration.SetString(
			"value",
			sBuffer
		);

		jFields.Push(
			jFieldDuration
		);
	}

	/*
	 * Communication type field.
	 */
	if (iType == Comms)
	{
		JsonObject jFieldCommType =
			view_as<JsonObject>(new Json("{}"));

		jFieldCommType.SetString(
			"name",
			"Comm Type"
		);

		char sCommType[32];

		GetCommType(
			sCommType,
			sizeof(sCommType),
			extra
		);

		jFieldCommType.SetString(
			"value",
			sCommType
		);

		jFields.Push(
			jFieldCommType
		);
	}

	/*
	 * Reason field.
	 */
	JsonObject jFieldReason =
		view_as<JsonObject>(new Json("{}"));

	jFieldReason.SetString(
		"name",
		"Reason"
	);

	jFieldReason.SetString(
		"value",
		sReason
	);

	jFields.Push(
		jFieldReason
	);

	jEmbed.Set(
		"fields",
		jFields
	);

	jEmbeds.Push(
		jEmbed
	);

	/*
	 * Complete the request.
	 */
	jRequest.SetString(
		"username",
		szUsername
	);

	jRequest.SetString(
		"avatar_url",
		szProfilePictureURL
	);

	jRequest.Set(
		"embeds",
		jEmbeds
	);

	#if defined DEBUG
		char sDebugJson[8192];

		if (jRequest.Dump(
			sDebugJson,
			sizeof(sDebugJson),
			Compact
		))
		{
			PrintToServer(
				"%s",
				sDebugJson
			);
		}
	#endif

	char sEndpoint[256];

	GetEndpoint(
		sEndpoint,
		sizeof(sEndpoint),
		iType
	);

	if (sEndpoint[0] == '\0')
	{
		delete jRequest;
		return;
	}

	if (!jRequest.Dump(
		sJson,
		sizeof(sJson),
		Compact,
		true
	))
	{
		LogError(
			"Could not encode Discord JSON payload"
		);

		return;
	}

	Handle hRequest = SteamWorks_CreateHTTPRequest(
		k_EHTTPMethodPOST,
		sEndpoint
	);

	if (hRequest == null)
	{
		LogError(
			"Could not create HTTP request for Discord webhook"
		);

		return;
	}

	SteamWorks_SetHTTPRequestContextValue(
		hRequest,
		iClient,
		iTarget
	);

	SteamWorks_SetHTTPRequestGetOrPostParameter(
		hRequest,
		"payload_json",
		sJson
	);

	SteamWorks_SetHTTPCallbacks(
		hRequest,
		OnHTTPRequestComplete
	);

	if (!SteamWorks_SendHTTPRequest(hRequest))
	{
		LogError(
			"HTTP request failed for %s against %s",
			sAuthor,
			sTarget
		);

		CloseHandle(hRequest);
	}
}


/*
 * HTTP completion callback.
 */
public void OnHTTPRequestComplete(
	Handle hRequest,
	bool bFailure,
	bool bRequestSuccessful,
	EHTTPStatusCode eStatusCode,
	int iClient,
	int iTarget
)
{
	if (
		bFailure ||
		!bRequestSuccessful ||
		eStatusCode != k_EHTTPStatusCode204NoContent
	)
	{
		LogError(
			"HTTP request failed for %N against %N",
			iClient,
			iTarget
		);

		#if defined DEBUG
			int iSize;

			SteamWorks_GetHTTPResponseBodySize(
				hRequest,
				iSize
			);

			if (iSize > 0)
			{
				char[] sBody = new char[iSize + 1];

				SteamWorks_GetHTTPResponseBodyData(
					hRequest,
					sBody,
					iSize
				);

				PrintToServer(
					"%s",
					sBody
				);
			}

			PrintToServer(
				"Status Code: %d",
				eStatusCode
			);

			PrintToServer(
				"SteamWorks_IsLoaded: %d",
				SteamWorks_IsLoaded()
			);
		#endif
	}

	CloseHandle(hRequest);
}


/*
 * ConVar change callback.
 */
public void OnConvarChanged(
	ConVar convar,
	const char[] oldValue,
	const char[] newValue
)
{
	if (convar == Convars[Ban])
	{
		Convars[Ban].GetString(
			sEndpoints[Ban],
			sizeof(sEndpoints[])
		);
	}
	else if (convar == Convars[Report])
	{
		Convars[Report].GetString(
			sEndpoints[Report],
			sizeof(sEndpoints[])
		);
	}
	else if (convar == Convars[Comms])
	{
		Convars[Comms].GetString(
			sEndpoints[Comms],
			sizeof(sEndpoints[])
		);
	}
	else if (convar == DiscordRoleID)
	{
		DiscordRoleID.GetString(
			sDiscordRoleID,
			sizeof(sDiscordRoleID)
		);
	}
}


/*
 * Returns the embed color for a report type.
 */
public int GetEmbedColor(int iType)
{
	if (iType != Type_Unknown)
	{
		return EmbedColors[iType];
	}

	return EmbedColors[Ban];
}

public void GetEndpoint(
	char[] sBuffer,
	int iBufferSize,
	int iType
)
{
	sBuffer[0] = '\0';

	if (
		iType != Ban &&
		iType != Report &&
		iType != Comms
	)
	{
		return;
	}

	if (sEndpoints[iType][0] == '\0')
	{
		return;
	}

	strcopy(
		sBuffer,
		iBufferSize,
		sEndpoints[iType]
	);
}

public void GetCommType(
	char[] sBuffer,
	int iBufferSize,
	int iType
)
{
	switch (iType)
	{
		case TYPE_MUTE:
		{
			strcopy(
				sBuffer,
				iBufferSize,
				"Mute"
			);
		}

		case TYPE_GAG:
		{
			strcopy(
				sBuffer,
				iBufferSize,
				"Gag"
			);
		}

		case TYPE_SILENCE:
		{
			strcopy(
				sBuffer,
				iBufferSize,
				"Silence"
			);
		}

		default:
		{
			strcopy(
				sBuffer,
				iBufferSize,
				"Unknown"
			);
		}
	}
}

/*
 * Validates a client index.
 */
stock bool IsValidClient(
	int iClient,
	bool bAlive = false
)
{
	if (
		iClient >= 1 &&
		iClient <= MaxClients &&
		IsClientConnected(iClient) &&
		IsClientInGame(iClient) &&
		!IsFakeClient(iClient) &&
		(
			!bAlive ||
			IsPlayerAlive(iClient)
		)
	)
	{
		return true;
	}

	return false;
}
