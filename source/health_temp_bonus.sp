#include <sourcemod>
#include <left4downtown>
#include <sdktools>

/* Ratio */
#define PERM_RATIO 0.7

/* Game constants */
#define REVIVE_HEALTH 30
#define NUMBER_SURVIVORS 4
#define NUMBER_REVIVES_BEFORE_BW 2
#define MAX_REVIVES 8 /* NUMBER_SURVIVORS * NUMBER_REVIVES_BEFORE_BW */
#define STOCK_TEMP_HEALTH 240 /* NUMBER_REVIVES_BEFORE_BW * NUMBER_SURVIVORS * REVIVE_HEALTH */
#define PAIN_PILLS_HEALTH 50

/* Health divisor to keep bonus at reasonable numbers */
#define HEALTH_DIVISOR 200

/* Health Index values */
#define HEALTH_TABLE_SIZE 6
#define PERM_HEALTH_INDEX 0
#define TEMP_HEALTH_INDEX 1
#define STOCK_TEMP_HEALTH_INDEX 2
#define PILLS_HEALTH_INDEX 3 
#define REVIVE_COUNT_INDEX 4
#define ALIVE_COUNT_INDEX 5

new Handle:hCvarValveSurvivalBonus;
new Handle:hCvarValveTieBreaker;
new bool:isFirstRound;
new firstRoundBonus;
new firstRoundHealth[HEALTH_TABLE_SIZE];

public Plugin myinfo =
{
	name = "L4D2 Competitive Health Bonus System",
	author = "Luckylock",
	description = "Scoring system for l4d2 competitive",
	version = "1.0",
	url = "https://github.com/LuckyServ/"
};

public OnPluginStart() 
{
    RegConsoleCmd("sm_health", Cmd_ShowBonus, "Show current bonus");
    hCvarValveSurvivalBonus = FindConVar("vs_survival_bonus");
    hCvarValveTieBreaker = FindConVar("vs_tiebreak_bonus");
}

public void OnMapStart() 
{
    isFirstRound = true;    
}

public Action Cmd_ShowBonus(client, args) 
{
    new health[HEALTH_TABLE_SIZE] = {0, 0, 0, 0, 0, 0};
    CalculateHealth(health);
    new finalBonus = CalculateFinalBonus(health);
    
    if (isFirstRound) {
        PrintRoundBonusAll(true, health, finalBonus);
    } else {
        PrintRoundBonusAll(true, firstRoundHealth, firstRoundBonus);    
        PrintRoundBonusAll(false, health, finalBonus);    
    }
}

public void CalculateHealth(int health[HEALTH_TABLE_SIZE]) 
{
    new revives = 0;

    for(new client = 1; client <= MaxClients; ++client) {
        if (IsSurvivor(client)) {
            if (IsPlayerAlive(client) && !L4D_IsPlayerIncapacitated(client)) {
                health[PERM_HEALTH_INDEX] += GetClientHealth(client);
                health[TEMP_HEALTH_INDEX] += GetTempHealth(client); 
                revives += L4D_GetPlayerReviveCount(client);
                health[ALIVE_COUNT_INDEX]++;
                if (HasPills(client)) {
                    health[PILLS_HEALTH_INDEX] += PAIN_PILLS_HEALTH; 
                }
            } else {
                revives += NUMBER_REVIVES_BEFORE_BW; 
            }
        }
    }

    health[STOCK_TEMP_HEALTH_INDEX] = STOCK_TEMP_HEALTH - (revives * REVIVE_HEALTH);
    health[REVIVE_COUNT_INDEX] = revives;
}

public int CalculateFinalBonus(health[HEALTH_TABLE_SIZE]) 
{
    health[PERM_HEALTH_INDEX] = 
        RoundFloat(health[PERM_HEALTH_INDEX] 
        * L4D_GetVersusMaxCompletionScore() 
        * PERM_RATIO / HEALTH_DIVISOR
        / NUMBER_SURVIVORS * health[ALIVE_COUNT_INDEX]
        / MAX_REVIVES * (MAX_REVIVES - health[REVIVE_COUNT_INDEX]));

    for (new i = TEMP_HEALTH_INDEX; i <= PILLS_HEALTH_INDEX; ++i) {
        health[i] = 
            RoundFloat(health[i]
            * L4D_GetVersusMaxCompletionScore() 
            * (1.0 - PERM_RATIO) / HEALTH_DIVISOR
            / NUMBER_SURVIVORS * health[ALIVE_COUNT_INDEX]
            / MAX_REVIVES * (MAX_REVIVES - health[REVIVE_COUNT_INDEX]));
    }

    return health[PERM_HEALTH_INDEX] 
            + health[TEMP_HEALTH_INDEX] 
            + health[STOCK_TEMP_HEALTH_INDEX]
            + health[PILLS_HEALTH_INDEX]; 
}

public int CalculateTotalTempHealth(health[HEALTH_TABLE_SIZE])
{
    return health[TEMP_HEALTH_INDEX]                             
                    + health[STOCK_TEMP_HEALTH_INDEX]                           
                    + health[PILLS_HEALTH_INDEX];
}

/** 
 * https://forums.alliedmods.net/showthread.php?t=144780 
 */
public int GetTempHealth(client) 
{
    new Float:buffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer"); 
    new Float:TempHealth = 0.0;

    if (buffer > 0) {
        new Float:difference = GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
        new Float:decay = GetConVarFloat(FindConVar("pain_pills_decay_rate"));
        new Float:constant = 1.0/decay;
        TempHealth = buffer - (difference / constant);
    }

    if (TempHealth < 0) {
        return 0;
    } else {
        return RoundFloat(TempHealth);
    }
}

stock bool:IsSurvivor(client)                                                   
{                                                                               
    return client > 0 && client < MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2; 
}

stock bool:L4D_IsPlayerIncapacitated(client)
{
	return bool:GetEntProp(client, Prop_Send, "m_isIncapacitated");
}

stock L4D_GetPlayerReviveCount(client) 
{
	return GetEntProp(client, Prop_Send, "m_currentReviveCount");
}

stock bool HasPills(client)
{
	new item = GetPlayerWeaponSlot(client, 4);

	if (IsValidEdict(item))
	{
		decl String:buffer[64];
		GetEdictClassname(item, buffer, sizeof(buffer));
		return StrEqual(buffer, "weapon_pain_pills");
	}

	return false;
}

public Action L4D2_OnEndVersusModeRound(bool:countSurvivors) {
    new health[HEALTH_TABLE_SIZE] = {0, 0, 0, 0, 0, 0};
    CalculateHealth(health);
    new finalBonus = CalculateFinalBonus(health);

    SetConVarInt(hCvarValveSurvivalBonus, finalBonus / health[ALIVE_COUNT_INDEX]); 
    SetConVarInt(hCvarValveTieBreaker, 0);

    if (isFirstRound) {
        firstRoundBonus = finalBonus;
        copyTableValues(health, firstRoundHealth);
        PrintRoundBonusAll(true, health, finalBonus);
    } else {
        PrintRoundBonusAll(true, firstRoundHealth, firstRoundBonus);    
        PrintRoundBonusAll(false, health, finalBonus);    
    }

    isFirstRound = false;

    return Plugin_Continue;
}

public void PrintRoundBonusAll(bool firstRound, int health[HEALTH_TABLE_SIZE], int finalBonus)
{
    PrintToChatAll("\x04#%d \x01Bonus: \x05%d \x01[ Perm = \x03%d \x01| Temp = \x03%d \x01 | Pills = \x03%d \x01]", 
        firstRound ? 1 : 2, finalBonus, health[PERM_HEALTH_INDEX], health[TEMP_HEALTH_INDEX] + health[STOCK_TEMP_HEALTH_INDEX], 
        health[PILLS_HEALTH_INDEX]); 
}

public void copyTableValues(int health[HEALTH_TABLE_SIZE], int healthCopy[HEALTH_TABLE_SIZE])
{
    for (new i = 0; i < HEALTH_TABLE_SIZE; ++i) {
        healthCopy[i] = health[i];
    }
}
