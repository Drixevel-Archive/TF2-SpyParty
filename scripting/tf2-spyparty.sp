/*****************************/
//Pragma
#pragma semicolon 1
#pragma newdecls required

/*****************************/
//Defines
#define PLUGIN_NAME "[TF2] Spy Party"
#define PLUGIN_DESCRIPTION "An experimental gamemode where you have to assassinate spies attempting to complete objectives."
#define PLUGIN_VERSION "1.0.0"

#define STATE_HIBERNATION -1
#define STATE_LOBBY 0
#define STATE_COUNTDOWN 1
#define STATE_PLAYING 2

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

Handle g_Hud;
int g_MatchState = STATE_HIBERNATION;

int g_Countdown;
Handle g_CountdownTimer;

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
	HookEvent("player_spawn", Event_OnPlayerSpawn);

	RegAdminCmd("sm_start", Command_Start, ADMFLAG_ROOT, "Start the match.");

	g_Hud = CreateHudSynchronizer();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		if (IsPlayerAlive(i))
			CreateTimer(0.1, Timer_DelaySpawn, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			ClearSyncHud(i, g_Hud);
}

public void OnMapEnd()
{
	g_CountdownTimer = null;
}

public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.1, Timer_DelaySpawn, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_DelaySpawn(Handle timer, any data)
{
	int client;
	if ((client = GetClientOfUserId(data)) == 0)
		return Plugin_Stop;
	
	switch (TF2_GetClientTeam(client))
	{
		case TFTeam_Red:
		{
			TF2_SetPlayerClass(client, TFClass_Sniper);
			TF2_RegeneratePlayer(client);
		}

		case TFTeam_Blue:
		{
			TF2_SetPlayerClass(client, view_as<TFClassType>(GetRandomInt(3, 9)));
			TF2_RegeneratePlayer(client);
		}
	}

	UpdateHud(client);

	return Plugin_Stop;
}

void UpdateHud(int client)
{
	char sMatchState[32];
	GetMatchStateName(sMatchState, sizeof(sMatchState));

	SetHudTextParams(0.0, 0.0, 99999.0, 255, 255, 255, 255);
	ShowSyncHudText(client, g_Hud, "Match State: %s", sMatchState);
}

void GetMatchStateName(char[] buffer, int size)
{
	switch (g_MatchState)
	{
		case STATE_HIBERNATION:
			strcopy(buffer, size, "Hibernation");
		case STATE_LOBBY:
			strcopy(buffer, size, "Waiting");
		case STATE_COUNTDOWN:
			strcopy(buffer, size, "Starting");
		case STATE_PLAYING:
			strcopy(buffer, size, "Live");
	}
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (g_MatchState != STATE_PLAYING)
	{
		SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetTime() + 999.0);
		SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetTime() + 999.0);
		SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", GetTime() + 999.0);
	}
}

public Action Command_Start(int client, int args)
{
	StartMatch();
	PrintToChat(client, "%N has started the match.", client);
	return Plugin_Handled;
}

void StartMatch()
{
	g_MatchState = STATE_COUNTDOWN;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		if (IsPlayerAlive(i))
		{
			SetEntPropFloat(i, Prop_Send, "m_flNextAttack", GetGameTime());

			int weapon;
			for (int slot = 0; slot < 3; slot++)
			{
				if ((weapon = GetPlayerWeaponSlot(i, slot)) != -1)
				{
					SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime());
					SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", GetGameTime());
				}
			}
		}

		TF2_RespawnPlayer(i);
	}

	g_Countdown = 5;
	StopTimer(g_CountdownTimer);
	g_CountdownTimer = CreateTimer(1.0, Timer_CountdownTick, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_CountdownTick(Handle timer)
{
	g_Countdown--;

	if (g_Countdown > 0)
	{
		PrintHintTextToAll("Match Starting in... %i", g_Countdown);
		return Plugin_Continue;
	}

	g_Countdown = 0;
	g_CountdownTimer = null;

	g_MatchState = STATE_PLAYING;
	PrintHintTextToAll("Match has started.");

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			UpdateHud(i);

	return Plugin_Stop;
}