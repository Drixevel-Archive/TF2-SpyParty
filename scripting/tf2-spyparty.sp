/*
Change Class Stations
Lockdown Walls
*/

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

#define ACTION_GIVE 0

/*****************************/
//Includes
#include <sourcemod>
#include <sdkhooks>
#include <dhooks>
#include <tf2_stocks>
#include <tf2items>
#include <tf2attributes>
#include <misc-colors>
#include <customkeyvalues>

/*****************************/
//ConVars

ConVar convar_TeamBalance;
ConVar convar_GivenTasks;

ConVar g_cvarLaserEnabled;
ConVar g_cvarLaserRandom;
ConVar g_cvarLaserRED;
ConVar g_cvarLaserBLU;

ConVar convar_AllTalk;
ConVar convar_RespawnWaveTime;
ConVar convar_AutoTeamBalance;
ConVar convar_TeamBalanceLimit;
ConVar convar_AutoScramble;

/*****************************/
//Globals

enum TF2Quality {
	TF2Quality_Normal = 0, // 0
	TF2Quality_Rarity1,
	TF2Quality_Genuine = 1,
	TF2Quality_Rarity2,
	TF2Quality_Vintage,
	TF2Quality_Rarity3,
	TF2Quality_Rarity4,
	TF2Quality_Unusual = 5,
	TF2Quality_Unique,
	TF2Quality_Community,
	TF2Quality_Developer,
	TF2Quality_Selfmade,
	TF2Quality_Customized, // 10
	TF2Quality_Strange,
	TF2Quality_Completed,
	TF2Quality_Haunted,
	TF2Quality_ToborA
};

int g_GlowSprite;

int g_IsAimingAt[MAXPLAYERS + 1] = {-1, ...};

Handle g_Hud;
int g_MatchState = STATE_HIBERNATION;

int g_LobbyTime;
Handle g_LobbyTimer;

int g_LockdownTime = -1;

bool g_IsChangingClasses[MAXPLAYERS + 1];
int g_LastChangedClass[MAXPLAYERS + 1] = {-1, ...};

int g_Countdown;
Handle g_CountdownTimer;

bool g_IsSpy[MAXPLAYERS + 1];
bool g_IsBenefactor[MAXPLAYERS + 1];

int g_BenefactorNoises[MAXPLAYERS + 1];

int g_LastRefilled[MAXPLAYERS + 1];

enum struct Tasks
{
	char name[128];
	char trigger[128];

	void Add(const char[] name, const char[] trigger)
	{
		strcopy(this.name, 128, name);
		strcopy(this.trigger, 128, trigger);
	}
}

Tasks g_Tasks[32];
int g_TotalTasks;

ArrayList g_RequiredTasks[MAXPLAYERS + 1];
int g_NearTask[MAXPLAYERS + 1] = {-1, ...};

int g_TotalTasksEx;
int g_TotalShots;

Handle g_OnWeaponFire;

int g_GiveTasks;
Handle g_GiveTasksTimer;

int g_GlowEnt[MAXPLAYERS + 1] = {-1, ...};

int g_SpyTask;

int g_iLaserMaterial;
int g_iHaloMaterial;

int g_QueuePoints[MAXPLAYERS + 1];

int g_iEyeProp[MAXPLAYERS + 1];
int g_iSniperDot[MAXPLAYERS + 1];
int g_iDotController[MAXPLAYERS + 1];

float g_TaskTimer[MAXPLAYERS + 1];
Handle g_DoingTask[MAXPLAYERS + 1];

bool g_IsMarked[MAXPLAYERS + 1];

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
	CSetPrefix("{darkblue}[{azure}SpyParty{darkblue}]{honeydew}");

	convar_TeamBalance = CreateConVar("sm_spyparty_teambalance", "0.35", "How many more reds should there be for blues?", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	convar_GivenTasks = CreateConVar("sm_spyparty_giventasks", "2", "How many tasks do players get per tick?", FCVAR_NOTIFY, true, 1.0);

	g_cvarLaserEnabled = CreateConVar("sm_spyparty_laser_enabled", "0", "Sniper rifles emit lasers", _, true, 0.0, true, 1.0);
	g_cvarLaserRandom = CreateConVar("sm_spyparty_laser_random_color", "0", "Sniper laser use random color?", _, true, 0.0, true, 1.0);
	g_cvarLaserRED = CreateConVar("sm_spyparty_laser_color_red", "255 0 0", "Sniper laser color RED");
	g_cvarLaserBLU = CreateConVar("sm_spyparty_laser_color_blu", "0 0 255", "Sniper laser color BLUE");

	convar_AllTalk = FindConVar("sv_alltalk");
	convar_RespawnWaveTime = FindConVar("mp_respawnwavetime");
	convar_AutoTeamBalance = FindConVar("mp_autoteambalance");
	convar_TeamBalanceLimit = FindConVar("mp_teams_unbalance_limit");
	convar_AutoScramble = FindConVar("mp_scrambleteams_auto");

	RegAdminCmd("sm_start", Command_Start, ADMFLAG_ROOT, "Start the match.");
	RegAdminCmd("sm_startmatch", Command_Start, ADMFLAG_ROOT, "Start the match.");
	RegAdminCmd("sm_givetask", Command_GiveTask, ADMFLAG_ROOT, "Give yourself or others a task.");
	RegAdminCmd("sm_spy", Command_Spy, ADMFLAG_ROOT, "Prints out who the spy is in chat.");
	RegAdminCmd("sm_setqueuepoints", Command_SetQueuePoints, ADMFLAG_ROOT, "Set your own or somebody else's queue points.");

	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_changeclass", Event_OnPlayerChangeClass);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("teamplay_round_start", Event_OnRoundStart);
	HookEvent("teamplay_round_win", Event_OnRoundEnd);

	AddCommandListener(Listener_VoiceMenu, "voicemenu");

	g_Hud = CreateHudSynchronizer();

	Handle config;
	if ((config = LoadGameConfigFile("tf2.spyparty")) != null)
	{
		int offset = GameConfGetOffset(config, "CBasePlayer::OnMyWeaponFired");
		
		if (offset != -1)
		{
			g_OnWeaponFire = DHookCreate(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity, OnMyWeaponFired);
			DHookAddParam(g_OnWeaponFire, HookParamType_Int);
		}
		
		delete config;
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		OnClientPutInServer(i);
		
		if (IsPlayerAlive(i))
			OnSpawn(i);
	}

	int entity = -1; char classname[64];
	while ((entity = FindEntityByClassname(entity, "*")) != -1)
		if (GetEntityClassname(entity, classname, sizeof(classname)))
			OnEntityCreated(entity, classname);
	
	ParseTasks();

	convar_RespawnWaveTime.IntValue = 10;
	convar_AutoTeamBalance.IntValue = 0;
	convar_TeamBalanceLimit.IntValue = 0;
	convar_AutoScramble.IntValue = 0;
}

public Action Command_Spy(int client, int args)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && g_IsSpy[i])
			CPrintToChat(client, "{azure}%N {honeydew}is currently a spy!", i);
	
	return Plugin_Handled;
}

public void OnConfigsExecuted()
{
	convar_RespawnWaveTime.IntValue = 10;
	convar_AutoTeamBalance.IntValue = 0;
	convar_TeamBalanceLimit.IntValue = 0;
	convar_AutoScramble.IntValue = 0;

	convar_AllTalk.BoolValue = true;
}

public void OnClientConnected(int client)
{
	g_QueuePoints[client] = 0;
}

public void OnClientPutInServer(int client)
{
	g_iEyeProp[client] = INVALID_ENT_REFERENCE;
	g_iSniperDot[client] = INVALID_ENT_REFERENCE;
	g_iDotController[client] = INVALID_ENT_REFERENCE;

	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

	delete g_RequiredTasks[client];
	g_RequiredTasks[client] = new ArrayList();

	if (g_OnWeaponFire != null)
		DHookEntity(g_OnWeaponFire, true, client);
}

public void OnClientDisconnect(int client)
{
	if (g_GlowEnt[client] > 0 && IsValidEntity(g_GlowEnt[client]))
		AcceptEntityInput(g_GlowEnt[client], "Kill");
}

public void OnClientDisconnect_Post(int client)
{
	g_IsSpy[client] = false;
	g_IsBenefactor[client] = false;
	g_IsMarked[client] = false;

	g_BenefactorNoises[client] = 0;

	g_LastRefilled[client] = 0;

	delete g_RequiredTasks[client];
	g_NearTask[client] = -1;

	g_GlowEnt[client] = -1;

	g_QueuePoints[client] = 0;

	g_IsChangingClasses[client] = false;
	g_LastChangedClass[client] = -1;
}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	if ((damagetype & DMG_BURN) == DMG_BURN)
		return Plugin_Continue;
	
	if ((damagetype & DMG_FALL) == DMG_FALL)
	{
		damage = 0.0;
		return Plugin_Changed;
	}

	damage = 500.0;
	return Plugin_Changed;
}

void ParseTasks()
{
	g_TotalTasks = 0;

	int entity = -1; char sClassname[64]; char sName[64];
	while ((entity = FindEntityByClassname(entity, "trigger_multiple")) != -1)
	{
		GetEntPropString(entity, Prop_Data, "m_iName", sClassname, sizeof(sClassname));

		if (StrContains(sClassname, "task_", false) != 0)
				continue;
		
		GetCustomKeyValue(entity, "task", sName,  sizeof(sName));
		
		g_Tasks[g_TotalTasks++].Add(sName, sClassname);
	}
}

void AddTask(int client, int task)
{
	if (g_IsSpy[client] && GetRandomInt(0, 10) > 2)
		task = g_SpyTask;
	
	if (g_RequiredTasks[client].FindValue(task) != -1)
		task = GetRandomInt(0, g_TotalTasks - 1);
	
	g_RequiredTasks[client].Push(task);
	CPrintToChat(client, "You have been given the task: {azure}%s", g_Tasks[task].name);
	UpdateHud(client);

	EmitSoundToClient(client, "coach/coach_go_here.wav");
}

bool CompleteTask(int client, int task)
{
	if (!HasTask(client, task))
		return false;
	
	int index = g_RequiredTasks[client].FindValue(task);
	g_RequiredTasks[client].Erase(index);

	CPrintToChat(client, "You have completed the task: {azure}%s", g_Tasks[task].name);

	EmitSoundToClient(client, "coach/coach_defend_here.wav");

	if (g_IsSpy[client] && task == g_SpyTask)
	{
		EmitSoundToAll("coach/coach_look_here.wav");
		g_TotalTasksEx++;
	}
	
	g_TotalTasksEx++;

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			UpdateHud(i);

	if (g_TotalTasksEx >= GetMaxTasks())
	{
		CPrintToChatAll("Blue team has completed all available tasks, Blue wins the round.");
		TF2_ForceWin(TFTeam_Blue);
		return true;
	}

	ShowTasksPanel(client);
	return true;
}

int GetTasksCount(int client)
{
	return g_RequiredTasks[client].Length;
}

bool HasTask(int client, int task)
{
	if (g_RequiredTasks[client].FindValue(task) != -1)
		return true;
	
	return false;
}

public Action Command_GiveTask(int client, int args)
{
	OpenTasksMenu(client, ACTION_GIVE);
	return Plugin_Handled;
}

void OpenTasksMenu(int client, int action)
{
	Menu menu = new Menu(MenuHandler_Tasks);
	menu.SetTitle("Pick a task:");

	char sID[16];
	for (int i = 0; i < g_TotalTasks; i++)
	{
		IntToString(i, sID, sizeof(sID));
		menu.AddItem(sID, g_Tasks[i].name);
	}
	
	PushMenuInt(menu, "action", action);

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Tasks(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[16];
			menu.GetItem(param2, sInfo, sizeof(sInfo));

			int task = StringToInt(sInfo);
			int chosen_action = GetMenuInt(menu, "action");

			switch (chosen_action)
			{
				case ACTION_GIVE:
				{
					AddTask(param1, task);
				}
			}

			OpenTasksMenu(param1, chosen_action);
		}

		case MenuAction_End:
			delete menu;
	}
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		if (!IsFakeClient(i))
			ClearSyncHud(i, g_Hud);

		if (IsPlayerAlive(i) && g_GlowEnt[i] > 0 && IsValidEntity(g_GlowEnt[i]))
			AcceptEntityInput(g_GlowEnt[i], "Kill");
		
		KillEyeProp(i);
	}

	PauseTF2Timer();
	convar_RespawnWaveTime.IntValue = 10;
}

public void OnMapStart()
{
	g_GlowSprite = PrecacheModel("sprites/blueglow2.vmt");

	PrecacheSound("coach/coach_go_here.wav");
	PrecacheSound("coach/coach_defend_here.wav");
	PrecacheSound("coach/coach_look_here.wav");

	PrecacheSound("ambient/alarms/doomsday_lift_alarm.wav");

	g_iLaserMaterial = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iHaloMaterial = PrecacheModel("materials/sprites/halo01.vmt");

	convar_RespawnWaveTime.IntValue = 10;
}

public void OnMapEnd()
{
	g_MatchState = STATE_HIBERNATION;

	g_LobbyTimer = null;
	g_CountdownTimer = null;
	g_GiveTasksTimer = null;

	convar_RespawnWaveTime.IntValue = 10;
}

public void Event_OnPlayerChangeClass(Event event, const char[] name, bool dontBroadcast)
{
	int client;
	if ((client = GetClientOfUserId(event.GetInt("userid"))) == 0)
		return;
	
	UpdateHud(client);
	KillEyeProp(client);
}

public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.2, Timer_DelaySpawn, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);

	if (g_MatchState == STATE_HIBERNATION)
		InitLobby();
}

public Action Timer_DelaySpawn(Handle timer, any data)
{
	int client;
	if ((client = GetClientOfUserId(data)) == 0)
		return Plugin_Stop;
	
	if (g_GlowEnt[client] > 0 && IsValidEntity(g_GlowEnt[client]))
	{
		AcceptEntityInput(g_GlowEnt[client], "Kill");
		g_GlowEnt[client] = -1;
	}
	
	OnSpawn(client);

	return Plugin_Stop;
}

void OnSpawn(int client, bool class = true)
{
	KillEyeProp(client);

	switch (TF2_GetClientTeam(client))
	{
		case TFTeam_Red:
		{
			TF2_SetPlayerClass(client, TFClass_Sniper);
			TF2_RegeneratePlayer(client);

			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Primary);
			TF2_GiveItem(client, "tf_weapon_sniperrifle", 14, TF2Quality_Normal, 0, "");
			EquipWeaponSlot(client, TFWeaponSlot_Primary);

			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Grenade);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Building);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_PDA);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Item1);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Item2);

			int entity;
			while ((entity = FindEntityByClassname(entity, "tf_wearable_")) != -1)
				if (GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
					TF2_RemoveWearable(client, entity);

			int weapon;
			for (int slot = 0; slot < 3; slot++)
				if ((weapon = GetPlayerWeaponSlot(client, slot)) != -1)
					SetWeaponAmmo(client, weapon, 1);
			
			TF2Attrib_RemoveMoveSpeedPenalty(client);
			TF2Attrib_ApplyMoveSpeedBonus(client, 0.8);
		}

		case TFTeam_Blue:
		{
			if (class)
				TF2_SetPlayerClass(client, GetRandomClass());
			TF2_RegeneratePlayer(client);

			EquipWeaponSlot(client, TFWeaponSlot_Melee);

			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Primary);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Grenade);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Building);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_PDA);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Item1);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Item2);

			int entity;
			while ((entity = FindEntityByClassname(entity, "tf_wearable_")) != -1)
				if (GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
					TF2_RemoveWearable(client, entity);

			g_GlowEnt[client] = TF2_CreateGlow("blue_glow", client);
			
			if (IsValidEntity(g_GlowEnt[client]))
				SDKHook(g_GlowEnt[client], SDKHook_SetTransmit, OnTransmitGlow);
			
			if (TF2_GetPlayerClass(client) == TFClass_Scout)
				TF2Attrib_ApplyMoveSpeedPenalty(client, 0.2);
			else
				TF2Attrib_RemoveMoveSpeedPenalty(client);
			
			TF2Attrib_RemoveMoveSpeedBonus(client);

			//Temporary fix for spawns in a map with no blue spawns.
			if (class)
				TeleportEntity(client, view_as<float>({-65.53, 24.58, 2755.0}), view_as<float>({-0.92, 90.71, 0.0}), NULL_VECTOR);
		}
	}

	if (!IsPlayerAlive(client))
		TF2_RespawnPlayer(client);

	if (g_MatchState == STATE_HIBERNATION)
		InitLobby();

	CreateTimer(0.2, Timer_Hud, GetClientUserId(client));
}

public Action OnTransmitGlow(int entity, int client)
{
	SetEdictFlags(entity, GetEdictFlags(entity) & ~FL_EDICT_ALWAYS);
	
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hTarget");

	if (owner < 1 || owner > MaxClients || client < 1 || client > MaxClients)
		return Plugin_Continue;
	
	if (owner == client || TF2_GetClientTeam(owner) == TF2_GetClientTeam(client))
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public Action Timer_Hud(Handle timer, any data)
{
	int client;
	if ((client = GetClientOfUserId(data)) > 0)
		UpdateHud(client);
}

stock int TF2_GiveItem(int client, char[] classname, int index, TF2Quality quality = TF2Quality_Normal, int level = 0, const char[] attributes = "")
{
	char sClass[64];
	strcopy(sClass, sizeof(sClass), classname);
	
	if (StrContains(sClass, "saxxy", false) != -1)
	{
		switch (TF2_GetPlayerClass(client))
		{
			case TFClass_Scout: strcopy(sClass, sizeof(sClass), "tf_weapon_bat");
			case TFClass_Sniper: strcopy(sClass, sizeof(sClass), "tf_weapon_club");
			case TFClass_Soldier: strcopy(sClass, sizeof(sClass), "tf_weapon_shovel");
			case TFClass_DemoMan: strcopy(sClass, sizeof(sClass), "tf_weapon_bottle");
			case TFClass_Engineer: strcopy(sClass, sizeof(sClass), "tf_weapon_wrench");
			case TFClass_Pyro: strcopy(sClass, sizeof(sClass), "tf_weapon_fireaxe");
			case TFClass_Heavy: strcopy(sClass, sizeof(sClass), "tf_weapon_fists");
			case TFClass_Spy: strcopy(sClass, sizeof(sClass), "tf_weapon_knife");
			case TFClass_Medic: strcopy(sClass, sizeof(sClass), "tf_weapon_bonesaw");
		}
	}
	else if (StrContains(sClass, "shotgun", false) != -1)
	{
		switch (TF2_GetPlayerClass(client))
		{
			case TFClass_Soldier: strcopy(sClass, sizeof(sClass), "tf_weapon_shotgun_soldier");
			case TFClass_Pyro: strcopy(sClass, sizeof(sClass), "tf_weapon_shotgun_pyro");
			case TFClass_Heavy: strcopy(sClass, sizeof(sClass), "tf_weapon_shotgun_hwg");
			case TFClass_Engineer: strcopy(sClass, sizeof(sClass), "tf_weapon_shotgun_primary");
		}
	}
	
	Handle item = TF2Items_CreateItem(PRESERVE_ATTRIBUTES | FORCE_GENERATION);	//Keep reserve attributes otherwise random issues will occur... including crashes.
	TF2Items_SetClassname(item, sClass);
	TF2Items_SetItemIndex(item, index);
	TF2Items_SetQuality(item, view_as<int>(quality));
	TF2Items_SetLevel(item, level);
	
	char sAttrs[32][32];
	int count = ExplodeString(attributes, " ; ", sAttrs, 32, 32);
	
	if (count > 1)
	{
		TF2Items_SetNumAttributes(item, count / 2);
		
		int i2;
		for (int i = 0; i < count; i += 2)
		{
			TF2Items_SetAttribute(item, i2, StringToInt(sAttrs[i]), StringToFloat(sAttrs[i + 1]));
			i2++;
		}
	}
	else
		TF2Items_SetNumAttributes(item, 0);

	int weapon = TF2Items_GiveNamedItem(client, item);
	delete item;
	
	if (StrEqual(sClass, "tf_weapon_builder", false) || StrEqual(sClass, "tf_weapon_sapper", false))
	{
		SetEntProp(weapon, Prop_Send, "m_iObjectType", 3);
		SetEntProp(weapon, Prop_Data, "m_iSubType", 3);
		SetEntProp(weapon, Prop_Send, "m_aBuildableObjectTypes", 0, _, 0);
		SetEntProp(weapon, Prop_Send, "m_aBuildableObjectTypes", 0, _, 1);
		SetEntProp(weapon, Prop_Send, "m_aBuildableObjectTypes", 0, _, 2);
		SetEntProp(weapon, Prop_Send, "m_aBuildableObjectTypes", 1, _, 3);
	}
	
	if (StrContains(sClass, "tf_weapon_", false) == 0)
		EquipPlayerWeapon(client, weapon);
	
	return weapon;
}

public void Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.5, Timer_CheckDeath, _, TIMER_FLAG_NO_MAPCHANGE);

	int client;
	if ((client = GetClientOfUserId(event.GetInt("userid"))) == 0)
		return;
	
	KillEyeProp(client);
	
	if (g_GlowEnt[client] > 0 && IsValidEntity(g_GlowEnt[client]))
	{
		AcceptEntityInput(g_GlowEnt[client], "Kill");
		g_GlowEnt[client] = -1;
	}
	
	if (TF2_GetClientTeam(client) != TFTeam_Blue || g_MatchState != STATE_PLAYING)
		return;
	
	if (g_IsSpy[client])
	{
		CPrintToChatAll("{azure}%N {honeydew}was a spy and has died!", client);
		TF2_SetPlayerClass(client, TFClass_Spy);
		g_IsSpy[client] = false;
	}
	else if (g_IsBenefactor[client])
	{
		CPrintToChatAll("{ancient}%N {honeydew}was a benefactor and has died!", client);
		g_IsBenefactor[client] = false;
	}
	else
	{
		CPrintToChatAll("{aliceblue}%N {honeydew}was NOT a spy and has died!", client);

		int attacker;
		if ((attacker = GetClientOfUserId(event.GetInt("attacker"))) != -1)
		{
			CPrintToChat(attacker, "You have shot the wrong target!");
			TF2_IgnitePlayer(attacker, attacker, 10.0);
		}
	}
}

public Action Timer_CheckDeath(Handle timer)
{
	if (g_MatchState == STATE_PLAYING)
	{
		int count;

		count = 0;
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
				count++;
		
		if (count < 1)
			TF2_ForceWin(TFTeam_Blue);
		
		count = 0;
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3)
				count++;
		
		if (count < 1)
			TF2_ForceWin(TFTeam_Red);
		
		count = 0;
		for (int i = 1; i <= MaxClients; i++)
			if (g_IsSpy[i])
				count++;
		
		if (count < 1)
		{
			CPrintToChatAll("Red has eliminated all spies on the Blue team, Red wins the round.");
			TF2_ForceWin(TFTeam_Red);
		}
	}
}

stock void TF2_ForceWin(TFTeam team = TFTeam_Unassigned)
{
	int iFlags = GetCommandFlags("mp_forcewin");
	SetCommandFlags("mp_forcewin", iFlags &= ~FCVAR_CHEAT);
	ServerCommand("mp_forcewin %i", view_as<int>(team));
	SetCommandFlags("mp_forcewin", iFlags);
}

void EquipWeaponSlot(int client, int slot)
{
	int iWeapon = GetPlayerWeaponSlot(client, slot);
	
	if (IsValidEntity(iWeapon))
	{
		char class[64];
		GetEntityClassname(iWeapon, class, sizeof(class));
		FakeClientCommand(client, "use %s", class);
	}
}

TFClassType GetRandomClass()
{
	TFClassType classes[7];

	classes[0] = TFClass_Scout;
	classes[1] = TFClass_Soldier;
	classes[2] = TFClass_DemoMan;
	classes[3] = TFClass_Medic;
	classes[4] = TFClass_Heavy;
	classes[5] = TFClass_Pyro;
	classes[6] = TFClass_Engineer;

	return classes[GetRandomInt(0, 6)];
}

void UpdateHudAll()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			UpdateHud(i);
}

void UpdateHud(int client)
{
	char sMatchState[32];
	GetMatchStateName(sMatchState, sizeof(sMatchState));

	char sTeamHud[64];
	if (g_MatchState == STATE_PLAYING)
	{
		switch (TF2_GetClientTeam(client))
		{
			case TFTeam_Red, TFTeam_Spectator:
			{
				FormatEx(sTeamHud, sizeof(sTeamHud), "Total Shots: %i/%i", g_TotalShots, GetMaxShots());
			}

			case TFTeam_Blue:
			{
				int tasks = GetTasksCount(client);
				FormatEx(sTeamHud, sizeof(sTeamHud), "Available Tasks: %i", tasks);
			}
		}
	}

	char sTotalTasks[64];
	if (g_MatchState == STATE_PLAYING)
		FormatEx(sTotalTasks, sizeof(sTotalTasks), "\nTotal Tasks: %i/%i", g_TotalTasksEx, GetMaxTasks());
	
	int count;
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayerAlive(i))
			count++;

	char sWarning[32];
	if (count < 3 && g_MatchState == STATE_LOBBY)
		FormatEx(sWarning, sizeof(sWarning), "(Requires 3 players to start)");

	SetHudTextParams(0.0, 0.0, 99999.0, 255, 255, 255, 255);
	ShowSyncHudText(client, g_Hud, "Match State: %s (Queue Points: %i)\n%s%s%s", sMatchState, g_QueuePoints[client], sTeamHud, sTotalTasks, sWarning);
}

int GetMaxTasks()
{
	int tasks;
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayerAlive(i) && TF2_GetClientTeam(i) == TFTeam_Blue)
			tasks += 5;
	
	return tasks;
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
	if (TF2_GetClientTeam(client) == TFTeam_Red)
	{
		int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

		if (g_MatchState == STATE_PLAYING)
		{
			if (TF2_IsPlayerInCondition(client, TFCond_Zoomed))
			{
				SetEntPropFloat(active, Prop_Send, "m_flChargedDamage", g_IsAimingAt[client] != -1 ? 150.0 : 1.0);

				float origin[3];
				if (GetClientLookOrigin(client, origin, false, 35.0))
				{
					//CreatePointGlow(origin, 0.95, 0.5, 50);

					float origin2[3];
					for (int i = 1; i <= MaxClients; i++)
					{
						if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(client) == GetClientTeam(i))
							continue;
						
						GetClientAbsOrigin(i, origin2);

						if (GetVectorDistance(origin, origin2) >= 250.0)
						{
							if (g_IsAimingAt[client] == i)
								g_IsAimingAt[client] = -1;
							
							continue;
						}
						
						if (g_IsAimingAt[client] == -1)
							g_IsAimingAt[client] = i;
					}
				}
			}
			else
				g_IsAimingAt[client] = -1;
		}
		else
		{
			SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetTime() + 999.0);

			if (active > 0)
			{
				SetEntPropFloat(active, Prop_Send, "m_flNextPrimaryAttack", GetTime() + 999.0);
				SetEntPropFloat(active, Prop_Send, "m_flNextSecondaryAttack", GetTime() + 999.0);
			}
		}
	}

	if (g_MatchState == STATE_PLAYING && TF2_GetClientTeam(client) == TFTeam_Blue)
	{
		for (int i = 0; i < g_RequiredTasks[client].Length; i++)
		{
			int task = g_RequiredTasks[client].Get(i);

			if (task == -1)
				continue;
			
			int entity = FindEntityByName(g_Tasks[task].trigger, "trigger_multiple");

			if (!IsValidEntity(entity))
				continue;
			
			float vecDestStart[3]; float vecDestEnd[3];
			GetAbsBoundingBox(entity, vecDestStart, vecDestEnd);
			Effect_DrawBeamBoxToClient(client, vecDestStart, vecDestEnd, g_iLaserMaterial, g_iHaloMaterial, 30, 30, 0.5, 2.0, 2.0, 1, 5.0, {0, 191, 255, 120}, 0);
		}
	}
}

stock bool GetClientLookOrigin(int client, float pOrigin[3], bool filter_players = true, float distance = 35.0)
{
	if (client == 0 || client > MaxClients || !IsClientInGame(client))
		return false;

	float vOrigin[3];
	GetClientEyePosition(client,vOrigin);

	float vAngles[3];
	GetClientEyeAngles(client, vAngles);

	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, filter_players ? TraceEntityFilterPlayer : TraceEntityFilterNone, client);
	bool bReturn = TR_DidHit(trace);

	if (bReturn)
	{
		float vStart[3];
		TR_GetEndPosition(vStart, trace);

		float vBuffer[3];
		GetAngleVectors(vAngles, vBuffer, NULL_VECTOR, NULL_VECTOR);

		pOrigin[0] = vStart[0] + (vBuffer[0] * -distance);
		pOrigin[1] = vStart[1] + (vBuffer[1] * -distance);
		pOrigin[2] = vStart[2] + (vBuffer[2] * -distance);
	}

	delete trace;
	return bReturn;
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask, any data)
{
	return entity > MaxClients || !entity;
}

public bool TraceEntityFilterNone(int entity, int contentsMask, any data)
{
	return entity != data;
}

stock void CreatePointGlow(float origin[3], float time = 0.95, float size = 0.5, int brightness = 50)
{
	TE_SetupGlowSprite(origin, g_GlowSprite, time, size, brightness);
	TE_SendToAll();
}

int FindEntityByName(const char[] name, const char[] classname = "*")
{
	int entity = -1; char temp[256];
	while ((entity = FindEntityByClassname(entity, classname)) != -1)
	{
		GetEntPropString(entity, Prop_Data, "m_iName", temp, sizeof(temp));
		
		if (StrEqual(temp, name, false))
			return entity;
	}
	
	return entity;
}

void GetAbsBoundingBox(int ent, float mins[3], float maxs[3], bool half = false)
{
    float origin[3];

    GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", origin);
    GetEntPropVector(ent, Prop_Data, "m_vecMins", mins);
    GetEntPropVector(ent, Prop_Data, "m_vecMaxs", maxs);

    mins[0] += origin[0];
    mins[1] += origin[1];
    mins[2] += origin[2];
    maxs[0] += origin[0];
    maxs[1] += origin[1];

    if (!half)
        maxs[2] += origin[2];
    else
        maxs[2] = mins[2];
}

void Effect_DrawBeamBoxToClient(int client, const float bottomCorner[3], const float upperCorner[3], int modelIndex, int haloIndex, int startFrame = 0, int frameRate = 30, float life = 5.0, float width = 5.0, float endWidth = 5.0, int fadeLength = 2, float amplitude = 1.0, const color[4] =  { 255, 0, 0, 255 }, int speed = 0)
{
	int clients[1]; clients[0] = client;
	Effect_DrawBeamBox(clients, 1, bottomCorner, upperCorner, modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
}

void Effect_DrawBeamBox(int[] clients, int numClients, const float bottomCorner[3], const float upperCorner[3], int modelIndex, int haloIndex, int startFrame = 0, int frameRate = 30, float life = 5.0, float width = 5.0, float endWidth = 5.0, int fadeLength = 2, float amplitude = 1.0, const color[4] =  { 255, 0, 0, 255 }, int speed = 0)
{
	float corners[8][3];

	for (int i = 0; i < 4; i++)
	{
		CopyArrayToArray(bottomCorner, corners[i], 3);
		CopyArrayToArray(upperCorner, corners[i + 4], 3);
	}

	corners[1][0] = upperCorner[0];
	corners[2][0] = upperCorner[0];
	corners[2][1] = upperCorner[1];
	corners[3][1] = upperCorner[1];
	corners[4][0] = bottomCorner[0];
	corners[4][1] = bottomCorner[1];
	corners[5][1] = bottomCorner[1];
	corners[7][0] = bottomCorner[0];

	for (int i = 0; i < 4; i++)
	{
		int j = (i == 3 ? 0 : i + 1);
		TE_SetupBeamPoints(corners[i], corners[j], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
		TE_Send(clients, numClients);
	}

	for (int i = 4; i < 8; i++)
	{
		int j = (i == 7 ? 4 : i + 1);
		TE_SetupBeamPoints(corners[i], corners[j], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
		TE_Send(clients, numClients);
	}

	for (int i = 0; i < 4; i++)
	{
		TE_SetupBeamPoints(corners[i], corners[i + 4], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
		TE_Send(clients, numClients);
	}
}

void CopyArrayToArray(const any[] array, any[] newArray, int size)
{
	for (int i = 0; i < size; i++)
		newArray[i] = array[i];
}

public Action Command_Start(int client, int args)
{
	StartMatch();
	CPrintToChat(client, "{azure}%N {honeydew}has started the match.", client);
	return Plugin_Handled;
}

void StartMatch()
{
	convar_AllTalk.BoolValue = false;

	if (GameRules_GetProp("m_bInWaitingForPlayers"))
		ServerCommand("mp_waitingforplayers_cancel 1");

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && TF2_GetClientTeam(i) == TFTeam_Red)
			TF2_ChangeClientTeam_Alive(i, TFTeam_Blue);
	
	g_LobbyTime = 0;
	StopTimer(g_LobbyTimer);

	g_MatchState = STATE_COUNTDOWN;

	CreateTF2Timer(5);

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

	g_LockdownTime = -1;

	g_Countdown = 0;
	g_CountdownTimer = null;

	g_MatchState = STATE_PLAYING;
	PrintHintTextToAll("Match has started.");

	g_TotalTasksEx = 0;
	g_TotalShots = 0;
	
	int count = TF2_GetTeamClientCount(TFTeam_Blue);
	int total = TF2_GetTeamClientCount(TFTeam_Red);
	int balance = RoundToFloor(count * convar_TeamBalance.FloatValue);

	//CPrintToChatAll("count: %i balance: %i - total: %i", count, balance, total);

	if (total < balance)
	{
		balance -= total;
		//CPrintToChatAll("moving %i...", balance);
		
		int moved; int failsafe; int client;
		while (moved < balance && failsafe < MaxClients)
		{
			if ((client = FindAssassinToMove()) != -1)
			{
				TF2_ChangeClientTeam(client, TFTeam_Red);
				TF2_RespawnPlayer(client);
				g_QueuePoints[client] = 0;
				moved++;
			}
			else
				failsafe++;
		}
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && TF2_GetClientTeam(i) == TFTeam_Blue)
		{
			g_QueuePoints[i]++;

			if (!IsPlayerAlive(i))
				TF2_RespawnPlayer(i);
		}
	}

	CreateTimer(0.2, Timer_PostStart, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

public Action Timer_PostStart(Handle timer)
{
	int spy = FindSpy();

	if (spy == -1)
	{
		g_MatchState = STATE_LOBBY;
		CPrintToChatAll("Aborting starting match, couldn't find a spy.");
		return Plugin_Stop;
	}
	
	g_IsSpy[spy] = true;
	PrintCenterText(spy, "YOU ARE THE SPY!");
	EmitSoundToClient(spy, "coach/coach_look_here.wav");

	if (IsValidEntity(g_GlowEnt[spy]))
	{
		int color[4];
		color[0] = 0;
		color[1] = 255;
		color[2] = 0;
		color[3] = 255;
		
		SetVariantColor(color);
		AcceptEntityInput(g_GlowEnt[spy], "SetGlowColor");
	}

	int benefactor = FindBenefactor();

	if (benefactor != -1)
	{
		g_IsBenefactor[benefactor] = true;
		PrintCenterText(benefactor, "YOU ARE A BENEFACTOR!");
		EmitSoundToClient(benefactor, "coach/coach_look_here.wav");

		if (IsValidEntity(g_GlowEnt[benefactor]))
		{
			int color[4];
			color[0] = 0;
			color[1] = 0;
			color[2] = 255;
			color[3] = 255;
			
			SetVariantColor(color);
			AcceptEntityInput(g_GlowEnt[benefactor], "SetGlowColor");
		}
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		g_LastRefilled[i] = 0;
		
		if (IsPlayerAlive(i))
		{
			SetEntPropFloat(i, Prop_Send, "m_flNextAttack", GetGameTime() + 15000.0);

			int weapon;
			for (int slot = 0; slot < 3; slot++)
			{
				if ((weapon = GetPlayerWeaponSlot(i, slot)) != -1)
				{
					SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + 15000.0);
					SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + 15000.0);
				}
			}

			if (TF2_GetClientTeam(i) == TFTeam_Red)
			{
				PrintCenterText(i, "You can take your 1st shot in 15 seconds...");
				CreateTimer(15.0, Timer_ShotAllowed, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
			}
		}

		TF2_RespawnPlayer(i);
		UpdateHud(i);

		switch (TF2_GetClientTeam(i))
		{
			case TFTeam_Red:
			{
				CPrintToChat(i, "Hunt out the spy and assassinate them! You have a limited amount of chances, use them wisely!");
				CPrintToChat(i, "Keep in mind that benefactors can fake you out!");

				int weapon;
				for (int slot = 0; slot < 3; slot++)
					if ((weapon = GetPlayerWeaponSlot(i, slot)) != -1)
						SetWeaponAmmo(i, weapon, 1);
			}

			case TFTeam_Blue:
			{
				CPrintToChat(i, "{azure}%N {honeydew}has been chosen as the Spy, protect them at all costs by doing basic tasks!", spy);

				if (benefactor != -1)
					CPrintToChat(i, "{ancient}%N {honeydew}is a benefactor!", benefactor);
			}
		}
	}

	convar_RespawnWaveTime.IntValue = 99999;
	CreateTF2Timer(900);

	g_SpyTask = GetRandomInt(0, g_TotalTasks - 1);
	CPrintToChat(spy, "Priority Task: {aqua}%s {honeydew}(Do this task the most to win the round)", g_Tasks[g_SpyTask].name);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && TF2_GetClientTeam(i) == TFTeam_Blue)
		{
			g_RequiredTasks[i].Clear();

			for (int x = 0; x < convar_GivenTasks.IntValue; x++)
				AddTask(i, GetRandomInt(0, g_TotalTasks - 1));
			
			ShowTasksPanel(i);
		}
	}

	g_GiveTasks = GetRandomInt(60, 80);
	StopTimer(g_GiveTasksTimer);
	g_GiveTasksTimer = CreateTimer(1.0, Timer_GiveTasksTick, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Stop;
}

public Action Timer_ShotAllowed(Handle timer, any data)
{
	int client;
	if ((client = GetClientOfUserId(data)) > 0 && IsClientInGame(client) && IsPlayerAlive(client) && TF2_GetClientTeam(client) == TFTeam_Red)
		PrintCenterText(client, "You may take your 1st shot!");
}

int TF2_GetTeamClientCount(TFTeam team)
{
	int value = 0;

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && TF2_GetClientTeam(i) == team)
			value++;

	return value;
}

int FindAssassinToMove()
{
	ArrayList queue = new ArrayList();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || TF2_GetClientTeam(i) != TFTeam_Blue)
			continue;
		
		queue.Push(i);
	}

	if (queue.Length < 1)
	{
		delete queue;
		return -1;
	}

	SortADTArrayCustom(queue, OnSortQueue);
	int client = queue.Get(0);
	delete queue;

	return client;
}

public int OnSortQueue(int index1, int index2, Handle array, Handle hndl)
{
	int client1 = GetArrayCell(array, index1);
	int client2 = GetArrayCell(array, index2);
	
	return g_QueuePoints[client2] - g_QueuePoints[client1];
}

public Action Timer_GiveTasksTick(Handle timer)
{
	g_GiveTasks--;

	if (g_GiveTasks > 0)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i))
				continue;
			
			PrintHintText(i, "Next tasks in: %i", g_GiveTasks);
			StopSound(i, SNDCHAN_STATIC, "UI/hint.wav");
		}

		return Plugin_Continue;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && TF2_GetClientTeam(i) == TFTeam_Blue)
		{
			g_RequiredTasks[i].Clear();

			for (int x = 0; x < convar_GivenTasks.IntValue; x++)
				AddTask(i, GetRandomInt(0, g_TotalTasks - 1));
			
			ShowTasksPanel(i);
		}
	}

	g_GiveTasks = GetRandomInt(60, 80);
	return Plugin_Continue;
}

void ShowTasksPanel(int client)
{
	Panel panel = new Panel();
	panel.SetTitle("Available Tasks:");

	char sDisplay[128];
	for (int i = 0; i < g_RequiredTasks[client].Length; i++)
	{
		int task = g_RequiredTasks[client].Get(i);
		FormatEx(sDisplay, sizeof(sDisplay), "Task %i: %s", i + 1, g_Tasks[task].name);
		panel.DrawText(sDisplay);
	}

	panel.Send(client, MenuAction_Void, MENU_TIME_FOREVER);
	delete panel;
}

public int MenuAction_Void(Menu menu, MenuAction action, int param1, int param2)
{

}

int GetWeaponAmmo(int client, int weapon)
{
	int iAmmoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	
	if (iAmmoType != -1)
		return GetEntProp(client, Prop_Data, "m_iAmmo", _, iAmmoType);
	
	return 0;
}

void SetWeaponAmmo(int client, int weapon, int ammo)
{
	int iAmmoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	
	if (iAmmoType != -1)
		SetEntProp(client, Prop_Data, "m_iAmmo", ammo, _, iAmmoType);
}

int FindSpy()
{
	int[] clients = new int[MaxClients];
	int amount;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || TF2_GetClientTeam(i) != TFTeam_Blue)
			continue;

		clients[amount++] = i;
	}

	if (amount == 0)
		return -1;

	return clients[GetRandomInt(0, amount - 1)];
}

int FindBenefactor()
{
	int[] clients = new int[MaxClients];
	int amount;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || TF2_GetClientTeam(i) != TFTeam_Blue || g_IsSpy[i])
			continue;

		clients[amount++] = i;
	}

	if (amount == 0)
		return -1;

	return clients[GetRandomInt(0, amount - 1)];
}

bool StopTimer(Handle& timer)
{
	if (timer != null)
	{
		KillTimer(timer);
		timer = null;
		return true;
	}
	
	return false;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "trigger_multiple", false))
	{
		SDKHook(entity, SDKHook_StartTouch, OnTouchTriggerStart);
		SDKHook(entity, SDKHook_Touch, OnTouchTrigger);
		SDKHook(entity, SDKHook_EndTouch, OnTouchTriggerEnd);
	}

	if (StrContains(classname, "ammo", false) != -1)
		SDKHook(entity, SDKHook_Spawn, OnBlockSpawn);
	
	if (StrEqual(classname, "env_sniperdot") && g_cvarLaserEnabled.BoolValue)
		SDKHook(entity, SDKHook_SpawnPost, SpawnPost);
	
	if (StrEqual(classname, "func_button", false))
		SDKHook(entity, SDKHook_OnTakeDamage, OnButtonUse);
}

public Action OnButtonUse(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	char sName[64];
	GetEntPropString(victim, Prop_Data, "m_iName", sName, sizeof(sName));

	int time = GetTime();

	if (StrEqual(sName, "lockdown", false))
	{
		if (g_LockdownTime > time)
		{
			EmitGameSoundToClient(attacker, "Player.DenyWeaponSelection");
			CPrintToChat(attacker, "You must wait another {azure}%i {honeydew} seconds to start another lockdown.", g_LockdownTime - time);
			damage = 0.0;
			return Plugin_Changed;
		}

		g_LockdownTime = time + 300;
		EmitSoundToAll("ambient/alarms/doomsday_lift_alarm.wav", victim);
	}

	return Plugin_Continue;
}

public Action SpawnPost(int entity)
{
	RequestFrame(SpawnPostPost, entity);	
}

public void SpawnPostPost(int ent)
{
	if (IsValidEntity(ent))
	{
		int client = GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity");
		
		if (client > 0 && client <= MaxClients && IsClientInGame(client))
		{
			///////////////////////////////////////////////
			float rgb[3]; 
			if (g_cvarLaserRandom.BoolValue)
			{
				rgb[0] = GetRandomFloat(0.0, 255.0);
				rgb[1] = GetRandomFloat(0.0, 255.0);
				rgb[2] = GetRandomFloat(0.0, 255.0);
			}
			else
			{
				char strrgb[PLATFORM_MAX_PATH];
			
				switch(TF2_GetClientTeam(client))
				{
					case TFTeam_Red:  g_cvarLaserRED.GetString(strrgb, PLATFORM_MAX_PATH);
					case TFTeam_Blue: g_cvarLaserBLU.GetString(strrgb, PLATFORM_MAX_PATH);
				}
				
				char rgbExploded[3][16];
				ExplodeString(strrgb, " ", rgbExploded, sizeof(rgbExploded), sizeof(rgbExploded[]));
				
				rgb[0] = StringToFloat(rgbExploded[0]);
				rgb[1] = StringToFloat(rgbExploded[1]);
				rgb[2] = StringToFloat(rgbExploded[2]);
			}
			
			char name[PLATFORM_MAX_PATH];
			Format(name, PLATFORM_MAX_PATH, "laser_%i", ent);
		
			//color controls the color and is for color only.//
			int color = CreateEntityByName("info_particle_system");
			DispatchKeyValue(color, "targetname", name);
			DispatchKeyValueVector(color, "origin", rgb);
			DispatchSpawn(color);
			
			//Start of beam -> parented to client.
			int a = CreateEntityByName("info_particle_system");
			DispatchKeyValue(a, "effect_name", "laser_sight_beam");
			DispatchKeyValue(a, "cpoint2", name);
			DispatchSpawn(a);
			
			SetVariantString("!activator");
			AcceptEntityInput(a, "SetParent", client);
			
			SetVariantString("eyeglow_R");
			AcceptEntityInput(a, "SetParentAttachment", client);
			
			//Dot controller, set as controlpointent on beam
			int dotController = CreateEntityByName("info_particle_system");
			
			float dotPos[3];
			GetEntPropVector(ent, Prop_Send, "m_vecOrigin", dotPos);
			
			DispatchKeyValueVector(dotController, "origin", dotPos);
			DispatchSpawn(dotController);
			
			//Start of beam -> control point ent set to env_sniperdot
			SetEntPropEnt(a, Prop_Data, "m_hControlPointEnts", dotController);
			SetEntPropEnt(a, Prop_Send, "m_hControlPointEnts", dotController);
			
			ActivateEntity(a);
			AcceptEntityInput(a, "Start");
			
			SetVariantString("OnUser1 !self:kill::0.1:1");
			AcceptEntityInput(color, "AddOutput");
			AcceptEntityInput(color, "FireUser1");
			
			g_iEyeProp[client]   = EntIndexToEntRef(a);
			g_iSniperDot[client] = EntIndexToEntRef(ent);
			g_iDotController[client] = EntIndexToEntRef(dotController);
			
			//Hide original dot.
			SDKHook(ent, SDKHook_SetTransmit, OnDotTransmit);
		}
	}
}

public Action OnDotTransmit(int entity, int client)
{
	return Plugin_Handled;
}

public void OnGameFrame()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
			
		int env_sniperdot = EntRefToEntIndex(g_iSniperDot[i]);
		int dotController = EntRefToEntIndex(g_iDotController[i]);

		if (env_sniperdot > 0 && dotController > 0)
		{
			float dotPos[3]; GetEntPropVector(env_sniperdot, Prop_Send, "m_vecOrigin", dotPos);
			DispatchKeyValueVector(dotController, "origin", dotPos);
		}
		else
		{
			if (env_sniperdot <= 0 && dotController > 0)
			{
				DispatchKeyValue(dotController, "origin", "99999 99999 99999");
				
				SetVariantString("OnUser1 !self:kill::0.1:1");
				AcceptEntityInput(dotController, "AddOutput");
				AcceptEntityInput(dotController, "FireUser1");
				
				g_iDotController[i] = INVALID_ENT_REFERENCE;
			}
		}
	}
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	if (TF2_GetPlayerClass(client) == TFClass_Sniper && condition == TFCond_Zoomed)
		KillEyeProp(client);
}

void KillEyeProp(int client)
{
	int iEyeProp = EntRefToEntIndex(g_iEyeProp[client]);
	
	if (iEyeProp != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(iEyeProp, "ClearParent");
		AcceptEntityInput(iEyeProp, "Stop");
		
		DispatchKeyValue(iEyeProp, "origin", "99999 99999 99999");
		
		SetVariantString("OnUser1 !self:kill::0.1:1");
		AcceptEntityInput(iEyeProp, "AddOutput");
		AcceptEntityInput(iEyeProp, "FireUser1");
		
		g_iEyeProp[client] = INVALID_ENT_REFERENCE;
	}
}

public Action OnBlockSpawn(int entity)
{
	return Plugin_Stop;
}

public Action OnTouchTriggerStart(int entity, int other)
{
	if (other < 1 || other > MaxClients)
		return;
	
	char sName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	int time = GetTime();

	if (StrEqual(sName, "refill_mag", false) && TF2_GetClientTeam(other) == TFTeam_Red && g_MatchState == STATE_PLAYING)
	{
		int weapon = GetEntPropEnt(other, Prop_Send, "m_hActiveWeapon");

		if (GetWeaponAmmo(other, weapon) > 0)
		{
			CPrintToChat(other, "Your sniper is already full.");
			EmitGameSoundToClient(other, "Player.DenyWeaponSelection");
			return;
		}

		if (g_LastRefilled[other] > time)
		{
			CPrintToChat(other, "You must wait {azure}%i {honeydew}seconds to refill your sniper.", g_LastRefilled[other] - time);
			EmitGameSoundToClient(other, "Player.DenyWeaponSelection");
			return;
		}

		g_LastRefilled[other] = time + 60;
		EmitGameSoundToClient(other, "AmmoPack.Touch");
		SetWeaponAmmo(other, weapon, 1);
		
		return;
	}
	else if (StrEqual(sName, "changing_room", false))
	{
		if (g_LastChangedClass[other] > time)
		{
			CPrintToChat(other, "You must wait {azure}%i {honeydew}seconds to change your class again.", g_LastChangedClass[other] - time);
			EmitGameSoundToClient(other, "Player.DenyWeaponSelection");
			return;
		}
		
		g_IsChangingClasses[other] = true;
		OpenClassChangeMenu(other);
		return;
	}

	int task = GetTaskByName(sName);

	if (task == -1 || TF2_GetClientTeam(other) != TFTeam_Blue)
		return;
	
	g_NearTask[other] = task;
	
	if (HasTask(other, task))
		CPrintToChat(other, "You have this task, press {beige}MEDIC! {honeydew}to start this task.");
}

void OpenClassChangeMenu(int client)
{
	Menu menu = new Menu(MenuHandler_ClassChange);
	menu.SetTitle("Pick a class:");

	menu.AddItem("1", "Scout");
	menu.AddItem("3", "Soldier");
	menu.AddItem("7", "Pyro");
	menu.AddItem("4", "Demoman");
	menu.AddItem("6", "Heavy");
	menu.AddItem("9", "Engineer");
	menu.AddItem("5", "Medic");
	menu.AddItem("2", "Sniper");
	menu.AddItem("8", "Spy");

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ClassChange(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (!g_IsChangingClasses[param1])
				return;
			
			int time = GetTime();

			if (g_LastChangedClass[param1] > time)
			{
				CPrintToChat(param1, "You must wait {azure}%i {honeydew}seconds to change your class again.", g_LastChangedClass[param1] - time);
				EmitGameSoundToClient(param1, "Player.DenyWeaponSelection");
				return;
			}
			
			char sInfo[32]; char sName[32];
			menu.GetItem(param2, sInfo, sizeof(sInfo), _, sName, sizeof(sName));

			TFClassType class = view_as<TFClassType>(StringToInt(sInfo));
			TF2_SetPlayerClass(param1, class, false, true);
			OnSpawn(param1, false);

			g_LastChangedClass[param1] = time + 30;
			CPrintToChat(param1, "You have switched your class to {azure}%s{honeydew}.", g_LastChangedClass[param1] - time, sName);
		}
		
		case MenuAction_End:
			delete menu;
	}
}

public Action OnTouchTrigger(int entity, int other)
{
	if (other < 1 || other > MaxClients)
		return;
	
	char sName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	if (StrEqual(sName, "", false))
	{
		
	}
}

public Action OnTouchTriggerEnd(int entity, int other)
{
	if (other < 1 || other > MaxClients)
		return;
	
	char sName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	if (StrEqual(sName, "changing_room", false))
	{
		g_IsChangingClasses[other] = false;
		CancelClientMenu(other);
		return;
	}

	int task = GetTaskByName(sName);

	if (task == -1 || g_NearTask[other] != task || TF2_GetClientTeam(other) != TFTeam_Blue)
		return;
	
	g_NearTask[other] = -1;
}

bool PushMenuInt(Menu menu, const char[] id, int value)
{
	if (menu == null || strlen(id) == 0)
		return false;
	
	char sBuffer[128];
	IntToString(value, sBuffer, sizeof(sBuffer));
	return menu.AddItem(id, sBuffer, ITEMDRAW_IGNORE);
}

int GetMenuInt(Menu menu, const char[] id, int defaultvalue = 0)
{
	if (menu == null || strlen(id) == 0)
		return defaultvalue;
	
	char info[128]; char data[128];
	for (int i = 0; i < menu.ItemCount; i++)
		if (menu.GetItem(i, info, sizeof(info), _, data, sizeof(data)) && StrEqual(info, id))
			return StringToInt(data);
	
	return defaultvalue;
}

int GetTaskByName(const char[] task)
{
	for (int i = 0; i < g_TotalTasks; i++)
		if (StrEqual(task, g_Tasks[i].trigger, false))
			return i;
	
	return -1;
}

public Action Listener_VoiceMenu(int client, const char[] command, int argc)
{
	char sVoice[32];
	GetCmdArg(1, sVoice, sizeof(sVoice));

	char sVoice2[32];
	GetCmdArg(2, sVoice2, sizeof(sVoice2));
	
	if (!StrEqual(sVoice, "0", false) || !StrEqual(sVoice2, "0", false) || g_MatchState != STATE_PLAYING)
		return Plugin_Continue;
	
	if (TF2_GetClientTeam(client) == TFTeam_Blue)
	{
		if (g_NearTask[client] != -1 && HasTask(client, g_NearTask[client]))
		{
			g_TaskTimer[client] = 10.0;
			StopTimer(g_DoingTask[client]);
			g_DoingTask[client] = CreateTimer(0.1, Timer_DoingTask, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}

		int time = GetTime();

		if (g_IsBenefactor[client] && g_BenefactorNoises[client] <= time)
		{
			g_BenefactorNoises[client] = time + 10;
			EmitSoundToAll("coach/coach_look_here.wav");
		}

		return Plugin_Stop;
	}
	else if (TF2_GetClientTeam(client) == TFTeam_Red)
	{
		int target = GetClientAimTarget(client, true);

		if (target == -1 || g_IsMarked[target])
			return Plugin_Stop;
		
		SpeakResponseConcept(client, "TLK_PLAYER_POSITIVE");
		SpeakResponseConcept(target, "TLK_PLAYER_NEGATIVE");
		
		if (IsValidEntity(g_GlowEnt[target]))
		{
			int color[4];
			color[0] = 0;
			color[1] = 0;
			color[2] = 255;
			color[3] = 255;
			
			SetVariantColor(color);
			AcceptEntityInput(g_GlowEnt[target], "SetGlowColor");

			g_IsMarked[target] = true;
			CreateTimer(30.0, Timer_ResetColor, target);
		}

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action Timer_ResetColor(Handle timer, any data)
{
	int client = data;

	if (IsValidEntity(g_GlowEnt[client]))
	{
		int color[4];
		color[0] = 255;
		color[1] = 255;
		color[2] = 255;
		color[3] = 255;
		
		SetVariantColor(color);
		AcceptEntityInput(g_GlowEnt[client], "SetGlowColor");

		g_IsMarked[client] = false;
	}
}

public Action Timer_DoingTask(Handle timer, any data)
{
	int client = data;

	g_TaskTimer[client] -= 0.1;

	if (g_NearTask[client] == -1)
	{
		g_DoingTask[client] = null;
		return Plugin_Stop;
	}

	if (g_TaskTimer[client] > 0.0)
	{
		PrintCenterText(client, "Doing Task... %i", RoundFloat(g_TaskTimer[client]));
		return Plugin_Continue;
	}

	CompleteTask(client, g_NearTask[client]);
	g_NearTask[client] = -1;

	g_DoingTask[client] = null;
	return Plugin_Stop;
}

public MRESReturn OnMyWeaponFired(int client, Handle hReturn, Handle hParams)
{
	if (client < 1 || client > MaxClients || !IsValidEntity(client) || !IsPlayerAlive(client))
		return MRES_Ignored;
	
	//int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	if (TF2_GetClientTeam(client) == TFTeam_Red)
	{
		if (g_IsAimingAt[client] != -1)
		{
			SDKHooks_TakeDamage(g_IsAimingAt[client], 0, client, 1000.0);
			g_IsAimingAt[client] = -1;
		}

		g_TotalShots++;
		SpeakResponseConcept(client, "TLK_FIREWEAPON");

		if (g_TotalShots >= GetMaxShots())
		{
			CreateTimer(1.0, Timer_WeaponFirePost, _, TIMER_FLAG_NO_MAPCHANGE);
			return MRES_Ignored;
		}
		
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i) && TF2_GetClientTeam(i) == TFTeam_Red)
				UpdateHud(i);
		
		if (g_LastRefilled[client] < 1)
			g_LastRefilled[client] = GetTime() + 10;
	}
	
	return MRES_Ignored;
}

public Action Timer_WeaponFirePost(Handle timer)
{
	if (g_MatchState != STATE_PLAYING)
		return Plugin_Stop;
	
	CPrintToChatAll("Red team has ran out of ammunition, Blue wins the round.");
	TF2_ForceWin(TFTeam_Blue);

	return Plugin_Stop;
}

int GetMaxShots()
{
	int shots;
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayerAlive(i) && TF2_GetClientTeam(i) == TFTeam_Red)
			shots += 2;
	
	return shots;
}

public Action OnClientCommand(int client, int args)
{
	char sCommand[32];
	GetCmdArg(0, sCommand, sizeof(sCommand));

	if (g_MatchState == STATE_PLAYING && TF2_GetClientTeam(client) > TFTeam_Spectator && (StrEqual(sCommand, "jointeam", false) || StrEqual(sCommand, "joinclass", false)))
		return Plugin_Stop;
	
	return Plugin_Continue;
}

public void Event_OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	convar_RespawnWaveTime.IntValue = 10;
	convar_AutoTeamBalance.IntValue = 0;
	convar_TeamBalanceLimit.IntValue = 0;
	convar_AutoScramble.IntValue = 0;

	bool available;
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayerAlive(i))
			available = true;
	
	if (available)
		g_MatchState = STATE_LOBBY;
}

public void Event_OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	convar_AllTalk.BoolValue = true;
	g_MatchState = STATE_HIBERNATION;

	g_Countdown = 0;
	StopTimer(g_CountdownTimer);

	g_LobbyTime = 0;
	StopTimer(g_LobbyTimer);

	for (int i = 1; i <= MaxClients; i++)
	{
		g_IsSpy[i] = false;
		g_IsBenefactor[i] = false;

		g_LastRefilled[i] = 0;

		if (g_RequiredTasks[i] != null)
			g_RequiredTasks[i].Clear();
		g_NearTask[i] = -1;

		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			if (TF2_GetClientTeam(i) == TFTeam_Red)
			{
				if (TF2_IsPlayerInCondition(i, TFCond_Zoomed))
					TF2_RemoveCondition(i, TFCond_Zoomed);
				
				if (TF2_IsPlayerInCondition(i, TFCond_Slowed))
					TF2_RemoveCondition(i, TFCond_Slowed);
			}

			if (g_GlowEnt[i] > 0 && IsValidEntity(g_GlowEnt[i]))
			{
				AcceptEntityInput(g_GlowEnt[i], "Kill");
				g_GlowEnt[i] = -1;
			}
		}
	}

	g_TotalTasksEx = 0;
	g_TotalShots = 0;

	g_GiveTasks = 0;
	StopTimer(g_GiveTasksTimer);

	convar_RespawnWaveTime.IntValue = 10;
}

int TF2_CreateGlow(const char[] name, int target, int color[4] = {255, 255, 255, 255})
{
	char sClassname[64];
	GetEntityClassname(target, sClassname, sizeof(sClassname));

	char sTarget[128];
	Format(sTarget, sizeof(sTarget), "%s%i", sClassname, target);
	DispatchKeyValue(target, "targetname", sTarget);

	int glow = CreateEntityByName("tf_glow");

	if (IsValidEntity(glow))
	{
		char sGlow[64];
		Format(sGlow, sizeof(sGlow), "%i %i %i %i", color[0], color[1], color[2], color[3]);

		DispatchKeyValue(glow, "targetname", name);
		DispatchKeyValue(glow, "target", sTarget);
		DispatchKeyValue(glow, "Mode", "1"); //Mode is currently broken.
		DispatchKeyValue(glow, "GlowColor", sGlow);
		DispatchSpawn(glow);
		
		SetVariantString("!activator");
		AcceptEntityInput(glow, "SetParent", target, glow);

		AcceptEntityInput(glow, "Enable");
	}

	return glow;
}

void CreateTF2Timer(int timer)
{
	int entity = FindEntityByClassname(-1, "team_round_timer");

	if (!IsValidEntity(entity))
		entity = CreateEntityByName("team_round_timer");

	char sTime[32];
	IntToString(timer, sTime, sizeof(sTime));
	
	DispatchKeyValue(entity, "reset_time", "1");
	DispatchKeyValue(entity, "auto_countdown", "0");
	DispatchKeyValue(entity, "timer_length", sTime);
	DispatchSpawn(entity);

	AcceptEntityInput(entity, "Resume");

	SetVariantInt(1);
	AcceptEntityInput(entity, "ShowInHUD");
}

void PauseTF2Timer()
{
	int entity = FindEntityByClassname(-1, "team_round_timer");

	if (!IsValidEntity(entity))
		entity = CreateEntityByName("team_round_timer");
	
	AcceptEntityInput(entity, "Pause");
}

stock void UnpauseTF2Timer()
{
	int entity = FindEntityByClassname(-1, "team_round_timer");

	if (!IsValidEntity(entity))
		entity = CreateEntityByName("team_round_timer");
	
	AcceptEntityInput(entity, "Resume");
}

stock void TF2Attrib_ApplyMoveSpeedBonus(int client, float value)
{
	TF2Attrib_SetByName(client, "move speed bonus", 1.0 + value);
	TF2_AddCondition(client, TFCond_SpeedBuffAlly, 0.0);
}

stock void TF2Attrib_RemoveMoveSpeedBonus(int client)
{
	TF2Attrib_RemoveByName(client, "move speed bonus");
	TF2_AddCondition(client, TFCond_SpeedBuffAlly, 0.0);
}

stock void TF2Attrib_ApplyMoveSpeedPenalty(int client, float value)
{
	TF2Attrib_SetByName(client, "move speed penalty", 1.0 - value);
	TF2_AddCondition(client, TFCond_SpeedBuffAlly, 0.0);
}

stock void TF2Attrib_RemoveMoveSpeedPenalty(int client)
{
	TF2Attrib_RemoveByName(client, "move speed penalty");
	TF2_AddCondition(client, TFCond_SpeedBuffAlly, 0.0);
}

void InitLobby()
{
	convar_AllTalk.BoolValue = true;

	g_MatchState = STATE_LOBBY;
	CreateTF2Timer(120);

	StopTimer(g_LobbyTimer);
	g_LobbyTime = 120;
	g_LobbyTimer = CreateTimer(1.0, Timer_StartMatch, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_StartMatch(Handle timer)
{
	if (GameRules_GetProp("m_bInWaitingForPlayers"))
		return Plugin_Continue;
	
	int count;
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayerAlive(i))
			count++;
	
	if (count < 3)
	{
		PauseTF2Timer();
		UpdateHudAll();
		return Plugin_Continue;
	}
	else
	{
		UnpauseTF2Timer();
		UpdateHudAll();
	}
	
	g_LobbyTime--;

	if (g_LobbyTime > 0)
		return Plugin_Continue;

	g_LobbyTime = 0;
	g_LobbyTimer = null;

	StartMatch();

	return Plugin_Stop;
}

public void TF2_OnWaitingForPlayersEnd()
{
	CreateTimer(0.2, Timer_Init);
}

public Action Timer_Init(Handle timer)
{
	InitLobby();
}

public Action Command_SetQueuePoints(int client, int args)
{
	int target = client;

	if (args > 0)
	{
		char sTarget[MAX_TARGET_LENGTH];
		GetCmdArg(1, sTarget, sizeof(sTarget));
		target = FindTarget(client, sTarget, false, false);

		if (target == -1)
		{
			CPrintToChat(client, "Target {azure}%s {honeydew}not found, please try again.", sTarget);
			return Plugin_Handled;
		}
	}

	char sPoints[32];
	GetCmdArg(args > 1 ? 2 : 1, sPoints, sizeof(sPoints));
	int points = StringToInt(sPoints);

	g_QueuePoints[target] = points;
	UpdateHud(target);

	if (client == target)
		CPrintToChat(client, "You have set your own queue points to {azure}%i{honeydew}.", g_QueuePoints[target]);
	else
	{
		CPrintToChat(client, "You have set {azure}%N{honeydew}'s queue points to {azure}%i{honeydew}.", target, g_QueuePoints[target]);
		CPrintToChat(target, "{azure}%N {honeydew}has set your queue points by {azure}%i{honeydew}.", client, g_QueuePoints[target]);
	}

	return Plugin_Handled;
}

stock bool TF2_ChangeClientTeam_Alive(int client, TFTeam team)
{
	if (client == 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) || team < TFTeam_Red || team > TFTeam_Blue)
		return false;

	int lifestate = GetEntProp(client, Prop_Send, "m_lifeState");
	SetEntProp(client, Prop_Send, "m_lifeState", 2);
	ChangeClientTeam(client, view_as<int>(team));
	SetEntProp(client, Prop_Send, "m_lifeState", lifestate);
	
	return true;
}

stock void SpeakResponseConcept(int client, const char[] concept, const char[] context = "", const char[] class = "")
{
	bool hascontext;

	//For class specific context basically.
	if (strlen(context) > 0)
	{
		SetVariantString(context);
		AcceptEntityInput(client, "AddContext");

		hascontext = true;
	}

	//dominations require you add more context to them for certain things.
	if (strlen(class) > 0)
	{
		char sClass[64];
		FormatEx(sClass, sizeof(sClass), "victimclass:%s", class);
		SetVariantString(sClass);
		AcceptEntityInput(client, "AddContext");

		hascontext = true;
	}

	SetVariantString(concept);
	AcceptEntityInput(client, "SpeakResponseConcept");

	if (hascontext)
		AcceptEntityInput(client, "ClearContext");
}