/*
Force players to do tasks.
Make it so you get 2-3 random tasks every 20-30 seconds
1 sniper per 3 blues
5 tasks per blue
2 shots per sniper
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

/*****************************/
//ConVars

/*****************************/
//Globals

Handle g_Hud;
int g_MatchState = STATE_HIBERNATION;

int g_Countdown;
Handle g_CountdownTimer;

bool g_IsSpy[MAXPLAYERS + 1];

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

int g_MaxTasks = 30;
int g_MaxShots = 4;

Handle g_OnWeaponFire;

int g_GiveTasks;
Handle g_GiveTasksTimer;

int g_GlowEnt[MAXPLAYERS + 1] = {-1, ...};

int g_SpyTask;

int g_iLaserMaterial;
int g_iHaloMaterial;

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
	RegAdminCmd("sm_start", Command_Start, ADMFLAG_ROOT, "Start the match.");
	RegAdminCmd("sm_givetask", Command_GiveTask, ADMFLAG_ROOT, "Give yourself or others a task.");
	RegAdminCmd("sm_spy", Command_Spy, ADMFLAG_ROOT, "Prints out who the spy is in chat.");

	HookEvent("player_spawn", Event_OnPlayerSpawn);
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
			TF2_RespawnPlayer(i);
	}

	int entity = -1; char classname[64];
	while ((entity = FindEntityByClassname(entity, "*")) != -1)
		if (GetEntityClassname(entity, classname, sizeof(classname)))
			OnEntityCreated(entity, classname);
	
	ParseTasks();

	FindConVar("mp_respawnwavetime").IntValue = 10;
	FindConVar("mp_autoteambalance").IntValue = 0;
	FindConVar("mp_teams_unbalance_limit").IntValue = 0;
	FindConVar("mp_scrambleteams_auto").IntValue = 0;
}

public Action Command_Spy(int client, int args)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && g_IsSpy[i])
			PrintToChat(client, "%N is currently a spy!", i);
	
	return Plugin_Handled;
}

public void OnConfigsExecuted()
{
	FindConVar("mp_respawnwavetime").IntValue = 10;
	FindConVar("mp_autoteambalance").IntValue = 0;
	FindConVar("mp_teams_unbalance_limit").IntValue = 0;
	FindConVar("mp_scrambleteams_auto").IntValue = 0;
}

public void OnClientPutInServer(int client)
{
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

	g_LastRefilled[client] = 0;

	delete g_RequiredTasks[client];
	g_NearTask[client] = -1;

	g_GlowEnt[client] = -1;
}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	if ((damagetype & DMG_BURN) == DMG_BURN)
		return Plugin_Continue;
	
	if (TF2_GetClientTeam(victim) == TFTeam_Blue && (damagetype & DMG_FALL) == DMG_FALL)
	{
		//KickClient(victim, "Suicide is illegal here.");
		damage = 0.0;
		return Plugin_Changed;
	}

	damage = 500.0;
	return Plugin_Changed;
}

void ParseTasks()
{
	g_TotalTasks = 0;
	g_Tasks[g_TotalTasks++].Add("Rearrange Boxes", "task_boxes");
	g_Tasks[g_TotalTasks++].Add("Manage Data", "task_data");
	g_Tasks[g_TotalTasks++].Add("Tighten the Valve", "task_valve");
	g_Tasks[g_TotalTasks++].Add("Paint a Painting", "task_paint");
	g_Tasks[g_TotalTasks++].Add("Plot World Domination", "task_plot");
	g_Tasks[g_TotalTasks++].Add("Make Food", "task_food");
	g_Tasks[g_TotalTasks++].Add("Play Pool", "task_pool");
}

void AddTask(int client, int task)
{
	if (g_IsSpy[client] && GetRandomInt(0, 10) > 2)
		task = g_SpyTask;
	
	g_RequiredTasks[client].Push(task);
	PrintToChat(client, "You have been given the task: %s", g_Tasks[task].name);
	UpdateHud(client);

	EmitSoundToClient(client, "coach/coach_go_here.wav");
}

bool CompleteTask(int client, int task)
{
	if (!HasTask(client, task))
		return false;
	
	int index = g_RequiredTasks[client].FindValue(task);
	g_RequiredTasks[client].Erase(index);

	PrintToChat(client, "You have completed the task: %s", g_Tasks[task].name);

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

	if (g_TotalTasksEx >= g_MaxTasks)
	{
		PrintToChatAll("Blue team has completed all available tasks, Blue wins the round.");
		TF2_ForceWin(TFTeam_Blue);
		return true;
	}

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
	}

	PauseTF2Timer();
	FindConVar("mp_respawnwavetime").IntValue = 10;
}

public void OnMapStart()
{
	PrecacheSound("coach/coach_go_here.wav");
	PrecacheSound("coach/coach_defend_here.wav");
	PrecacheSound("coach/coach_look_here.wav");

	g_iLaserMaterial = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iHaloMaterial = PrecacheModel("materials/sprites/halo01.vmt");

	FindConVar("mp_respawnwavetime").IntValue = 10;
}

public void OnMapEnd()
{
	g_MatchState = STATE_HIBERNATION;
	g_CountdownTimer = null;
	g_GiveTasksTimer = null;

	FindConVar("mp_respawnwavetime").IntValue = 10;
}

public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.2, Timer_DelaySpawn, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
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
	
	switch (TF2_GetClientTeam(client))
	{
		case TFTeam_Red:
		{
			TF2_SetPlayerClass(client, TFClass_Sniper);
			TF2_RegeneratePlayer(client);

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
		}

		case TFTeam_Blue:
		{
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
		}
	}

	UpdateHud(client);

	return Plugin_Stop;
}

public void Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.5, Timer_CheckDeath, _, TIMER_FLAG_NO_MAPCHANGE);

	int client;
	if ((client = GetClientOfUserId(event.GetInt("userid"))) == 0)
		return;
	
	if (g_GlowEnt[client] > 0 && IsValidEntity(g_GlowEnt[client]))
	{
		AcceptEntityInput(g_GlowEnt[client], "Kill");
		g_GlowEnt[client] = -1;
	}
	
	if (TF2_GetClientTeam(client) != TFTeam_Blue || g_MatchState != STATE_PLAYING)
		return;
	
	if (g_IsSpy[client])
	{
		PrintToChatAll("%N was a spy and has died!", client);
		TF2_SetPlayerClass(client, TFClass_Spy);
		g_IsSpy[client] = false;
	}
	else
	{
		PrintToChatAll("%N was NOT a spy and has died!", client);

		int attacker;
		if ((attacker = GetClientOfUserId(event.GetInt("attacker"))) != -1)
		{
			PrintToChat(attacker, "You have shot the wrong target!");
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
			PrintToChatAll("Red has eliminated all spies on the Blue team, Red wins the round.");
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

void UpdateHud(int client)
{
	char sMatchState[32];
	GetMatchStateName(sMatchState, sizeof(sMatchState));

	char sTeamHud[64];
	switch (TF2_GetClientTeam(client))
	{
		case TFTeam_Red:
		{
			FormatEx(sTeamHud, sizeof(sTeamHud), "Total Shots: %i/%i", g_TotalShots, g_MaxShots);
		}

		case TFTeam_Blue:
		{
			int tasks = GetTasksCount(client);
			FormatEx(sTeamHud, sizeof(sTeamHud), "Available Tasks: %i", tasks);
		}
	}

	SetHudTextParams(0.0, 0.0, 99999.0, 255, 255, 255, 255);
	ShowSyncHudText(client, g_Hud, "Match State: %s\n%s\nTotal Tasks: %i/%i", sMatchState, sTeamHud, g_TotalTasksEx, g_MaxTasks);
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
	if (g_MatchState != STATE_PLAYING && TF2_GetClientTeam(client) == TFTeam_Red)
	{
		SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetTime() + 999.0);

		if (weapon > 0)
		{
			SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetTime() + 999.0);
			SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", GetTime() + 999.0);
		}
	}

	if (g_MatchState == STATE_PLAYING && TF2_GetClientTeam(client) == TFTeam_Blue)
	{
		int task = g_NearTask[client];

		if (task == -1)
			return;
		
		int entity = FindEntityByName(g_Tasks[task].trigger, "trigger_multiple");

		if (!IsValidEntity(entity))
			return;
		
		float vecDestStart[3]; float vecDestEnd[3];
		GetAbsBoundingBox(entity, vecDestStart, vecDestEnd);
		Effect_DrawBeamBoxToClient(client, vecDestStart, vecDestEnd, g_iLaserMaterial, g_iHaloMaterial, 30, 30, 0.5, 5.0, 5.0, 1, 5.0, {210, 0, 0, 120}, 0);
	}
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
	PrintToChat(client, "%N has started the match.", client);
	return Plugin_Handled;
}

void StartMatch()
{
	g_MatchState = STATE_COUNTDOWN;

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

	g_TotalTasksEx = 0;
	g_TotalShots = 0;

	int spy = GetRandomClient();

	if (spy == -1)
	{
		g_MatchState = STATE_LOBBY;
		PrintToChatAll("Aborting starting match, couldn't find a spy.");
		return Plugin_Stop;
	}
	
	g_IsSpy[spy] = true;
	PrintCenterText(spy, "YOU ARE THE SPY!");
	EmitSoundToClient(spy, "coach/coach_look_here.wav");
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		g_LastRefilled[i] = 0;
		
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
		UpdateHud(i);

		switch (TF2_GetClientTeam(i))
		{
			case TFTeam_Red:
			{
				PrintToChat(i, "Hunt out the spy and assassinate them! You have a limited amount of chances, use them wisely!");

				int weapon;
				for (int slot = 0; slot < 3; slot++)
					if ((weapon = GetPlayerWeaponSlot(i, slot)) != -1)
						SetWeaponAmmo(i, weapon, 1);
			}

			case TFTeam_Blue:
			{
				PrintToChat(i, "%N has been chosen as the Spy, protect them at all costs by doing basic tasks!", spy);
			}
		}
	}

	FindConVar("mp_respawnwavetime").IntValue = 99999;
	CreateTF2Timer(900);

	g_SpyTask = GetRandomInt(0, g_TotalTasks - 1);
	PrintToChat(spy, "Priority Task: %s (Do this task the most to win the round)", g_Tasks[g_SpyTask].name);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && TF2_GetClientTeam(i) == TFTeam_Blue)
		{
			g_RequiredTasks[i].Clear();
			AddTask(i, GetRandomInt(0, g_TotalTasks - 1));
			AddTask(i, GetRandomInt(0, g_TotalTasks - 1));
			//AddTask(i, GetRandomInt(0, g_TotalTasks - 1));
			ShowTasksPanel(i);
		}
	}

	g_GiveTasks = GetRandomInt(60, 80);
	StopTimer(g_GiveTasksTimer);
	g_GiveTasksTimer = CreateTimer(1.0, Timer_GiveTasksTick, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Stop;
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
			AddTask(i, GetRandomInt(0, g_TotalTasks - 1));
			AddTask(i, GetRandomInt(0, g_TotalTasks - 1));
			//AddTask(i, GetRandomInt(0, g_TotalTasks - 1));
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

int GetRandomClient()
{
	int[] clients = new int[MaxClients];
	int amount;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || IsFakeClient(i) || GetClientTeam(i) != 3)
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

	if (StrEqual(sName, "refill_mag", false) && TF2_GetClientTeam(other) == TFTeam_Red)
	{
		int weapon = GetEntPropEnt(other, Prop_Send, "m_hActiveWeapon");

		if (GetWeaponAmmo(other, weapon) > 0)
		{
			PrintToChat(other, "Your sniper is already full.");
			EmitGameSoundToClient(other, "Player.DenyWeaponSelection");
			return;
		}

		if (g_LastRefilled[other] > time)
		{
			PrintToChat(other, "You must wait %i seconds to refill your sniper.", g_LastRefilled[other] - time);
			EmitGameSoundToClient(other, "Player.DenyWeaponSelection");
			return;
		}

		g_LastRefilled[other] = time + 60;
		EmitGameSoundToClient(other, "AmmoPack.Touch");
		SetWeaponAmmo(other, weapon, 1);
		
		return;
	}

	int task = GetTaskByName(sName);

	if (task == -1 || TF2_GetClientTeam(other) != TFTeam_Blue)
		return;
	
	g_NearTask[other] = task;
	
	if (HasTask(other, task))
	{
		PrintToChat(other, "You have this task, press MEDIC! to start this task.");
	}
	else
	{
		PrintToChat(other, "You don't have this task, move to a task that you have.");
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
	
	if (!StrEqual(sVoice, "0", false) || !StrEqual(sVoice2, "0", false))
		return Plugin_Continue;
	
	if (TF2_GetClientTeam(client) == TFTeam_Blue && g_NearTask[client] != -1 && HasTask(client, g_NearTask[client]))
	{
		CompleteTask(client, g_NearTask[client]);
		g_NearTask[client] = -1;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public MRESReturn OnMyWeaponFired(int client, Handle hReturn, Handle hParams)
{
	if (client < 1 || client > MaxClients || !IsValidEntity(client) || !IsPlayerAlive(client))
		return MRES_Ignored;
	
	//int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	if (TF2_GetClientTeam(client) == TFTeam_Red)
	{
		g_TotalShots++;

		if (g_TotalShots >= g_MaxShots)
		{
			PrintToChatAll("Red team has ran out of ammunition, Blue wins the round.");
			TF2_ForceWin(TFTeam_Blue);
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

public Action OnClientCommand(int client, int args)
{
	char sCommand[32];
	GetCmdArg(0, sCommand, sizeof(sCommand));

	if (g_MatchState == STATE_PLAYING && (StrEqual(sCommand, "jointeam", false) || StrEqual(sCommand, "joinclass", false)))
		return Plugin_Stop;
	
	return Plugin_Continue;
}

public void Event_OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			UpdateHud(i);
	
	FindConVar("mp_respawnwavetime").IntValue = 10;
	FindConVar("mp_autoteambalance").IntValue = 0;
	FindConVar("mp_teams_unbalance_limit").IntValue = 0;
	FindConVar("mp_scrambleteams_auto").IntValue = 0;
}

public void Event_OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_MatchState = STATE_HIBERNATION;

	g_Countdown = 0;
	StopTimer(g_CountdownTimer);

	for (int i = 1; i <= MaxClients; i++)
	{
		g_IsSpy[i] = false;

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

	FindConVar("mp_respawnwavetime").IntValue = 10;
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