#pragma semicolon 1

#include <sourcemod>
#include <neotokyo>

public Plugin:myinfo =
{
    name = "NEOTOKYO° Temporary score saver",
    author = "soft as HELL",
    description = "Saves score when player disconnects and restores it if player connects back before map change",
    version = "0.3",
    url = "https://github.com/softashell/nt-sourcemod-plugins"
};

new Handle:hDB, Handle:hRestartGame, Handle:hResetScoresTimer;
new bool:bScoreLoaded[MAXPLAYERS+1], bool:bResetScores;
new Handle:nt_savescore_database;

public OnPluginStart()
{
	nt_savescore_database = CreateConVar("nt_savescore_database", "nt_savescores", "Database filename for saving scores", FCVAR_PLUGIN|FCVAR_PROTECTED);
	
	hRestartGame = FindConVar("neo_restart_this");

	// Hook restart command
	if (hRestartGame != INVALID_HANDLE)
		HookConVarChange(hRestartGame, RestartGame);

	AddCommandListener(cmd_JoinTeam, "jointeam");

	HookEvent("game_round_start", event_RoundStart);

	bResetScores = false;
}

public OnConfigsExecuted()
{	
	// Create new database if it doesn't exist
	DB_init();

	// Clear it if we're reloading plugin or just started it
	DB_clear();
	
	bResetScores = false;
}

public RestartGame(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(StringToInt(newValue) == 0)
		return; // Not restarting

	if(hResetScoresTimer != INVALID_HANDLE)
		CloseHandle(hResetScoresTimer);

	new Float:fTimer = StringToFloat(newValue);

	hResetScoresTimer = CreateTimer(fTimer - 0.1, ResetScoresNextRound);
}

public Action:ResetScoresNextRound(Handle:timer)
{
	bResetScores = true;

	hResetScoresTimer = INVALID_HANDLE;
}

public OnClientDisconnect(client)
{
	//if(!bScoreLoaded[client])
	//	return; // Never tried to load score
	//I know this is a failsafe, but disabling this is the only way to have all this working somehow -glub

	DB_insertScore(client);

	bScoreLoaded[client] = false;
}

public Action:cmd_JoinTeam(client, const String:command[], args)
{ 
	decl String:cmd[3];
	GetCmdArgString(cmd, sizeof(cmd));

	new team_current = GetClientTeam(client);
	new team_target = StringToInt(cmd);

	if(!IsValidClient(client))
		return;

	if(IsPlayerAlive(client))
		return; // Alive player switching team, should never happen when you just connect

	if(team_current == team_target && team_target != 0 && team_current != 0)
		return; // Trying to join same team

	// Score isn't loaded from DB yet
	if(!bScoreLoaded[client])
		DB_retrieveScore(client);
}

public Action:event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!bResetScores)
		return;
	
	bResetScores = false;
	
	DB_clear();
}

DB_init()
{
	new String:error[255];
	new String:buffer[50];
	GetConVarString(nt_savescore_database, buffer, sizeof(buffer));
	
	hDB = SQLite_UseDatabase(buffer, error, sizeof(error));
	
	if (hDB == INVALID_HANDLE)
		SetFailState("SQL error: %s", error);
	
	SQL_LockDatabase(hDB);

	SQL_FastQuery(hDB, "VACUUM");
	SQL_FastQuery(hDB, "CREATE TABLE IF NOT EXISTS nt_saved_score (steamID TEXT PRIMARY KEY, xp SMALLINT, deaths SMALLINT);");
	
	SQL_UnlockDatabase(hDB);
}

DB_clear()
{
	SQL_LockDatabase(hDB);

	SQL_FastQuery(hDB, "DELETE FROM nt_saved_score;");

	SQL_UnlockDatabase(hDB);
}

DB_insertScore(client)
{
	if(!IsValidClient(client))
		return;

	decl String:steamID[30], String:query[200];
	new xp, deaths;
	
	GetClientAuthId(client, AuthId_SteamID64, steamID, sizeof(steamID));

	xp = GetPlayerXP(client);
	deaths = GetPlayerDeaths(client);
	
	Format(query, sizeof(query), "INSERT OR REPLACE INTO nt_saved_score VALUES ('%s', %d, %d);", steamID, xp, deaths);
	
	SQL_FastQuery(hDB, query);
}

DB_deleteScore(client)
{
	if(!IsValidClient(client))
		return;

	decl String:steamID[30], String:query[200];

	GetClientAuthId(client, AuthId_SteamID64, steamID, sizeof(steamID));

	Format(query, sizeof(query), "DELETE FROM nt_saved_score WHERE steamID = '%s';", steamID);

	SQL_FastQuery(hDB, query);
}

DB_retrieveScore(client)
{
	if(!IsValidClient(client))
		return;

	bScoreLoaded[client] = true; // At least we tried!

	decl String:steamID[30], String:query[200];
	
	GetClientAuthId(client, AuthId_SteamID64, steamID, sizeof(steamID));

	Format(query, sizeof(query), "SELECT * FROM	nt_saved_score WHERE steamID = '%s';", steamID);

	SQL_TQuery(hDB, DB_retrieveScoreCallback, query, client);
}

public DB_retrieveScoreCallback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL Error: %s", error);
		return;
	}

	if(!IsValidClient(client))
		return;

	if (SQL_GetRowCount(hndl) == 0)
		return;

	new xp = SQL_FetchInt(hndl, 1);
	new deaths = SQL_FetchInt(hndl, 2);

	if(xp != 0 || deaths != 0)
	{
		SetPlayerXP(client, xp);
		SetPlayerDeaths(client, deaths);
	}

	PrintToChat(client, "[NT°] Saved score restored!");
	PrintToConsole(client, "[NT°] Saved score restored! XP: %d Deaths: %d", xp, deaths);

	// Remove score from DB after it has been loaded
	DB_deleteScore(client);
}
