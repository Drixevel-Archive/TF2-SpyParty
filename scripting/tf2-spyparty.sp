/*****************************/
//Pragma
#pragma semicolon 1
#pragma newdecls required

/*****************************/
//Defines
#define PLUGIN_NAME "[TF2] Invisifortress"
#define PLUGIN_DESCRIPTION "An experimental gamemode involving invisibility."
#define PLUGIN_VERSION "1.0.0"

/*****************************/
//Includes
#include <sourcemod>
#include <misc-sm>
#include <misc-tf>
#include <misc-colors>

/*****************************/
//ConVars

/*****************************/
//Globals
int g_ShowPlayer[MAXPLAYERS + 1] = {-1, ...};
bool g_CloakSound[MAXPLAYERS + 1];
Handle g_Sync_Invisible;

/*****************************/
//Plugin Info
public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = "Drixevel", 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = "https://drixevel.dev/"
};

public void OnPluginStart()
{
	g_Sync_Invisible = CreateHudSynchronizer();

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			SDKHook(i, SDKHook_SetTransmit, OnSetTransmit);
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			ClearSyncHud(i, g_Sync_Invisible);
}

public void OnMapStart()
{
	PrecacheSound("misc/rd_finale_beep01.wav");
}

public void TF2_OnPlayerSpawn(int client, int team, int class)
{
	if (TF2_GetPlayerClass(client) == TFClass_Spy)
		TF2_RemoveWeaponSlot(client, TFWeaponSlot_Building);
}

public void TF2_OnRegeneratePlayerPost(int client)
{
	if (TF2_GetPlayerClass(client) == TFClass_Spy)
		TF2_RemoveWeaponSlot(client, TFWeaponSlot_Building);
}

public void OnGameFrame()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayerAlive(i))
			TF2_AddCondition(i, TFCond_StealthedUserBuffFade, TFCondDuration_Infinite);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_SetTransmit, OnSetTransmit);
}

public Action OnSetTransmit(int entity, int client)
{
	if (!IsPlayerIndex(client) || !IsPlayerAlive(client) || entity == client)
		return Plugin_Continue;
	
	if (g_ShowPlayer[entity] != -1 && g_ShowPlayer[entity] > GetTime())
	{
		SetHudTextParams(-1.0, 0.2, 3.0, 255, 0, 0, 255);
		ShowSyncHudText(entity, g_Sync_Invisible, "Visible");

		g_CloakSound[entity] = true;
		SetEntityFlags(entity, (GetEntityFlags(entity) &~ FL_NOTARGET));

		return Plugin_Continue;
	}

	SetEntityFlags(entity, (GetEntityFlags(entity) | FL_NOTARGET));

	if (g_CloakSound[entity])
	{
		g_CloakSound[entity] = false;
		EmitSoundToClient(entity, "misc/rd_finale_beep01.wav");
	}
		
	SetHudTextParams(-1.0, 0.2, 3.0, 0, 255, 0, 255);
	ShowSyncHudText(entity, g_Sync_Invisible, "Invisible");

	return Plugin_Continue;
}

public void TF2_OnWeaponFirePost(int client, int weapon)
{
	g_ShowPlayer[client] = GetTime() + 2;
}

public void TF2_OnPlayerDamagedPost(int victim, TFClassType victimclass, int attacker, TFClassType attackerclass, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom, bool alive)
{
	if (victim > 0 && (damagetype & DMG_FALL) == DMG_FALL)
		g_ShowPlayer[victim] = GetTime() + 2;
}