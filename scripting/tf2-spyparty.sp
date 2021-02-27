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

	HookEvent("player_spawn", Event_OnPlayerSpawn);

	AddCommandListener(Listener_VoiceMenu, "voicemenu");

	g_Hud = CreateHudSynchronizer();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		OnClientPutInServer(i);
		
		if (IsPlayerAlive(i))
			CreateTimer(0.1, Timer_DelaySpawn, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
	}

	int entity = -1; char classname[64];
	while ((entity = FindEntityByClassname(entity, "*")) != -1)
		if (GetEntityClassname(entity, classname, sizeof(classname)))
			OnEntityCreated(entity, classname);
	
	ParseTasks();
}

public void OnClientPutInServer(int client)
{
	delete g_RequiredTasks[client];
	g_RequiredTasks[client] = new ArrayList();
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
	g_RequiredTasks[client].Push(task);
	PrintToChat(client, "You have been given the task: %s", g_Tasks[task].name);
	UpdateHud(client);
}

bool CompleteTask(int client, int task)
{
	if (!HasTask(client, task))
		return false;
	
	int index = g_RequiredTasks[client].FindValue(task);
	g_RequiredTasks[client].Erase(index);

	PrintToChat(client, "You have completed the task: %s", g_Tasks[task].name);
	UpdateHud(client);

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

			EquipWeaponSlot(client, TFWeaponSlot_Primary);

			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Grenade);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Building);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_PDA);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Item1);
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Item2);

			int weapon;
			for (int slot = 0; slot < 3; slot++)
			{
				if ((weapon = GetPlayerWeaponSlot(client, slot)) != -1)
				{
					SetWeaponAmmo(client, weapon, 1);
					TF2Attrib_SetByName(weapon, "maxammo primary reduced", 10.0);
				}
			}
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
		}
	}

	UpdateHud(client);

	return Plugin_Stop;
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

	int tasks = GetTasksCount(client);

	SetHudTextParams(0.0, 0.0, 99999.0, 255, 255, 255, 255);
	ShowSyncHudText(client, g_Hud, "Match State: %s\nAvailable Tasks: %i", sMatchState, tasks);
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

		if (weapon > 0)
		{
			SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetTime() + 999.0);
			SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", GetTime() + 999.0);
		}
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

	int spy = GetRandomClient(true, false, true, view_as<int>(TFTeam_Blue));

	if (spy == -1)
	{
		g_MatchState = STATE_LOBBY;
		PrintToChatAll("Aborting starting match, couldn't find a spy.");
		return Plugin_Stop;
	}
	
	g_IsSpy[spy] = true;
	
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
		UpdateHud(i);

		switch (TF2_GetClientTeam(i))
		{
			case TFTeam_Red:
			{
				PrintToChat(i, "Hunt out the spy and assassinate them! You have a limited amount of chances, use them wisely!");

				int weapon;
				for (int slot = 0; slot < 3; slot++)
				{
					if ((weapon = GetPlayerWeaponSlot(i, slot)) != -1)
					{
						SetWeaponAmmo(i, weapon, 1);
						TF2Attrib_SetByName(weapon, "maxammo primary reduced", 10.0);
					}
				}
			}

			case TFTeam_Blue:
			{
				PrintToChat(i, "%N has been chosen as the Spy, protect them at all costs by doing basic tasks!", spy);
			}
		}
	}

	return Plugin_Stop;
}

void SetWeaponAmmo(int client, int weapon, int ammo)
{
	int iAmmoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	
	if (iAmmoType != -1)
		SetEntProp(client, Prop_Data, "m_iAmmo", ammo, _, iAmmoType);
}

int GetRandomClient(bool ingame = true, bool alive = false, bool fake = false, int team = 0)
{
	int[] clients = new int[MaxClients];
	int amount;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (ingame && !IsClientInGame(i) || alive && !IsPlayerAlive(i) || !fake && IsFakeClient(i) || team > 0 && team != GetClientTeam(i))
			continue;

		clients[amount++] = i;
	}

	return (amount == 0) ? -1 : clients[GetRandomInt(0, amount - 1)];
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

public Action TF2Items_OnGiveNamedItem(int client, char[] classname, int iItemDefinitionIndex, Handle& hItem)
{
	if (TF2_GetClientTeam(client) == TFTeam_Red)
	{
		hItem = TF2Items_CreateItem(PRESERVE_ATTRIBUTES | OVERRIDE_ATTRIBUTES);
		TF2Items_SetNumAttributes(hItem, 1);
		TF2Items_SetAttribute(hItem, 0, 77, 10.0);
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "trigger_multiple", false))
	{
		SDKHook(entity, SDKHook_StartTouch, OnTouchTriggerStart);
		SDKHook(entity, SDKHook_Touch, OnTouchTrigger);
		SDKHook(entity, SDKHook_EndTouch, OnTouchTriggerEnd);
	}
}

public Action OnTouchTriggerStart(int entity, int other)
{
	if (other < 1 || other > MaxClients)
		return;
	
	char sName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	int time = GetTime();

	if (StrEqual(sName, "refill_mag", false))
	{
		if (g_LastRefilled[other] > time)
		{
			PrintToChat(other, "You must wait %i seconds to refill your sniper.", g_LastRefilled[other] - time);
			EmitGameSoundToClient(other, "Player.DenyWeaponSelection");
			return;
		}

		g_LastRefilled[other] = time + 60;
		EmitGameSoundToClient(other, "AmmoPack.Touch");

		int weapon;
		for (int slot = 0; slot < 3; slot++)
			if ((weapon = GetPlayerWeaponSlot(other, slot)) != -1)
				SetWeaponAmmo(other, weapon, 1);
		
		return;
	}

	int task = GetTaskByName(sName);

	if (task == -1)
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

	if (task == -1 || g_NearTask[other] != task)
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
	
	if (g_NearTask[client] != -1 && HasTask(client, g_NearTask[client]))
	{
		CompleteTask(client, g_NearTask[client]);
		g_NearTask[client] = -1;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}