#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_AUTHOR "RumbleFrog, SourceBans++ Dev Team"
#define PLUGIN_VERSION "1.2.0"

#include <sourcemod>
#include <sourcebanspp>
#include <sourcecomms>
#include <SteamWorks>
#include <jansson>

enum
{
	Ban,
	Report,
	Comms,
	Type_Count,
	Type_Unknown,
};

int EmbedColors[Type_Count] =
{
	0xDA1D87,
	0xF9D942,
	0x4362FA,
};

ConVar Convars[Type_Count],
	Username,
	ProfilePictureURL,
	WebsiteBaseURL,
	DiscordRoleID;

char sEndpoints[Type_Count][256],
	sHostname[64],
	sHost[64],
	sDiscordRoleID[32];

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

	AutoExecConfig(true, "sbpp_discord");

	Convars[Ban].AddChangeHook(OnConvarChanged);
	Convars[Report].AddChangeHook(OnConvarChanged);
	Convars[Comms].AddChangeHook(OnConvarChanged);
	DiscordRoleID.AddChangeHook(OnConvarChanged);
}

public void OnConfigsExecuted()
{
	FindConVar("hostname").GetString(sHostname, sizeof sHostname);

	int ip[4];
	if (SteamWorks_GetPublicIP(ip))
	{
		Format(sHost, sizeof sHost, "%d.%d.%d.%d:%d", ip[0], ip[1], ip[2], ip[3], FindConVar("hostport").IntValue);
	}
	else
	{
		int ipAddress = FindConVar("hostip").IntValue;
		Format(sHost, sizeof sHost, "%d.%d.%d.%d:%d", ipAddress >> 24 & 0x000000FF, ipAddress >> 16 & 0x000000FF, ipAddress >> 8 & 0x000000FF, ipAddress & 0x000000FF, FindConVar("hostport").IntValue);
	}

	Convars[Ban].GetString(sEndpoints[Ban], sizeof sEndpoints[]);
	Convars[Report].GetString(sEndpoints[Report], sizeof sEndpoints[]);
	Convars[Comms].GetString(sEndpoints[Comms], sizeof sEndpoints[]);
	DiscordRoleID.GetString(sDiscordRoleID, sizeof sDiscordRoleID);
}

public void SBPP_OnBanPlayer(int admin, int target, int time, const char[] reason)
{
	if (sEndpoints[Ban][0] != '\0')
		SendReport(admin, target, reason, Ban, time);
}

public void SourceComms_OnBlockAdded(int admin, int target, int time, int commType, char[] reason)
{
	if (sEndpoints[Comms][0] != '\0')
		SendReport(admin, target, reason, Comms, time, commType);
}

public void SBPP_OnReportPlayer(int reporter, int target, const char[] reason)
{
	if (sEndpoints[Report][0] != '\0')
		SendReport(reporter, target, reason, Report);
}

void SendReport(int client, int target, const char[] reason, int type = Ban, int time = -1, int extra = 0)
{
	if (!IsValidClient(target))
		return;

	char author[MAX_NAME_LENGTH], targetName[MAX_NAME_LENGTH], authorID[32], targetID64[32], targetID[32];
	char json[2048], buffer[512], username[128], profilePictureURL[256], websiteURL[512];

	ProfilePictureURL.GetString(profilePictureURL, sizeof profilePictureURL);
	Username.GetString(username, sizeof username);

	if (IsValidClient(client))
	{
		GetClientName(client, author, sizeof author);
		GetClientAuthId(client, AuthId_Steam2, authorID, sizeof authorID);
	}
	else
	{
		strcopy(author, sizeof author, "Console");
		strcopy(authorID, sizeof authorID, "N/A");
	}

	GetClientAuthId(target, AuthId_SteamID64, targetID64, sizeof targetID64);
	GetClientName(target, targetName, sizeof targetName);
	GetClientAuthId(target, AuthId_Steam2, targetID, sizeof targetID);

	JsonObject request = NewJsonObject();
	JsonArray embeds = NewJsonArray();
	JsonObject embed = NewJsonObject();
	JsonObject fields = NewJsonArray();

	embed.SetInt("color", GetEmbedColor(type));
	WebsiteBaseURL.GetString(websiteURL, sizeof websiteURL);

	if (type == Report && sDiscordRoleID[0] != '\0')
	{
		Format(buffer, sizeof buffer, "<@&%s>", sDiscordRoleID);
		request.SetString("content", buffer);
	}

	if (websiteURL[0] != '\0')
	{
		embed.SetString("title", "View on Sourcebans");
		if (type == Comms)
			Format(buffer, sizeof buffer, "%s/index.php?p=commslist&searchText=%s", websiteURL, targetID);
		else if (type == Ban)
			Format(buffer, sizeof buffer, "%s/index.php?p=banlist&searchText=%s", websiteURL, targetID);
		else
			Format(buffer, sizeof buffer, "%s/index.php?p=admin&c=bans#^2", websiteURL);
		embed.SetString("url", buffer);
	}

	JsonObject authorObject = NewJsonObject();
	authorObject.SetString("name", targetName);
	Format(buffer, sizeof buffer, "https://steamcommunity.com/profiles/%s", targetID64);
	authorObject.SetString("url", buffer);
	authorObject.SetString("icon_url", profilePictureURL);
	embed.Set("author", authorObject);
	delete authorObject;

	JsonObject footer = NewJsonObject();
	Format(buffer, sizeof buffer, "%s (%s)", sHostname, sHost);
	footer.SetString("text", buffer);
	footer.SetString("icon_url", profilePictureURL);
	embed.Set("footer", footer);
	delete footer;

	JsonObject authorField = NewJsonObject();
	authorField.SetString("name", "Author");
	Format(buffer, sizeof buffer, "%s (%s)", author, authorID);
	authorField.SetString("value", buffer);
	authorField.SetBool("inline", true);
	asJSONA(fields).Push(authorField);
	delete authorField;

	JsonObject targetField = NewJsonObject();
	targetField.SetString("name", "Target");
	Format(buffer, sizeof buffer, "%s (%s)", targetName, targetID);
	targetField.SetString("value", buffer);
	targetField.SetBool("inline", true);
	asJSONA(fields).Push(targetField);
	delete targetField;

	if (type == Ban || type == Comms)
	{
		JsonObject durationField = NewJsonObject();
		durationField.SetString("name", "Duration");
		if (time > 0)
			Format(buffer, sizeof buffer, "%d Minutes", time);
		else if (time < 0)
			strcopy(buffer, sizeof buffer, "Session");
		else
			strcopy(buffer, sizeof buffer, "Permanent");
		durationField.SetString("value", buffer);
		asJSONA(fields).Push(durationField);
		delete durationField;
	}

	if (type == Comms)
	{
		JsonObject commTypeField = NewJsonObject();
		char commTypeName[32];
		commTypeField.SetString("name", "Comm Type");
		GetCommType(commTypeName, sizeof commTypeName, extra);
		commTypeField.SetString("value", commTypeName);
		asJSONA(fields).Push(commTypeField);
		delete commTypeField;
	}

	JsonObject reasonField = NewJsonObject();
	reasonField.SetString("name", "Reason");
	reasonField.SetString("value", reason);
	asJSONA(fields).Push(reasonField);
	delete reasonField;

	embed.Set("fields", fields);
	delete fields;
	asJSONA(embeds).Push(embed);
	delete embed;

	request.SetString("username", username);
	request.SetString("avatar_url", profilePictureURL);
	request.Set("embeds", embeds);
	delete embeds;

	if (!request.Dump(json, sizeof json, Compact, true))
	{
		delete request;
		return;
	}

#if defined DEBUG
	PrintToServer(json);
#endif

	char endpoint[256];
	GetEndpoint(endpoint, sizeof endpoint, type);
	Handle requestHandle = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, endpoint);
	SteamWorks_SetHTTPRequestContextValue(requestHandle, client, target);
	SteamWorks_SetHTTPRequestGetOrPostParameter(requestHandle, "payload_json", json);
	SteamWorks_SetHTTPCallbacks(requestHandle, OnHTTPRequestComplete);

	if (!SteamWorks_SendHTTPRequest(requestHandle))
		LogError("HTTP request failed for %s against %s", author, targetName);
}

JsonObject NewJsonObject()
{
	return view_as<JsonObject>(new Json("{}"));
}

JsonArray NewJsonArray()
{
	return view_as<JsonArray>(new Json("[]"));
}

public void OnHTTPRequestComplete(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode, int client, int target)
{
	if (!requestSuccessful || statusCode != k_EHTTPStatusCode204NoContent)
	{
		LogError("HTTP request failed for %N against %N", client, target);
#if defined DEBUG
		int size;
		SteamWorks_GetHTTPResponseBodySize(request, size);
		char[] body = new char[size];
		SteamWorks_GetHTTPResponseBodyData(request, body, size);
		PrintToServer(body);
		PrintToServer("Status Code: %d", statusCode);
		PrintToServer("SteamWorks_IsLoaded: %d", SteamWorks_IsLoaded());
#endif
	}

	delete request;
}

public void OnConvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == Convars[Ban])
		Convars[Ban].GetString(sEndpoints[Ban], sizeof sEndpoints[]);
	else if (convar == Convars[Report])
		Convars[Report].GetString(sEndpoints[Report], sizeof sEndpoints[]);
	else if (convar == Convars[Comms])
		Convars[Comms].GetString(sEndpoints[Comms], sizeof sEndpoints[]);
	else if (convar == DiscordRoleID)
		DiscordRoleID.GetString(sDiscordRoleID, sizeof sDiscordRoleID);
}

int GetEmbedColor(int type)
{
	if (type != Type_Unknown)
		return EmbedColors[type];
	return EmbedColors[Ban];
}

void GetEndpoint(char[] buffer, int bufferSize, int type)
{
	strcopy(buffer, bufferSize, sEndpoints[type]);
}

void GetCommType(char[] buffer, int bufferSize, int type)
{
	switch (type)
	{
		case TYPE_MUTE: strcopy(buffer, bufferSize, "Mute");
		case TYPE_GAG: strcopy(buffer, bufferSize, "Gag");
		case TYPE_SILENCE: strcopy(buffer, bufferSize, "Silence");
		default: strcopy(buffer, bufferSize, "Unknown");
	}
}

stock bool IsValidClient(int client, bool alive = false)
{
	return client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client) && (!alive || IsPlayerAlive(client));
}
