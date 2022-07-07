#include <geoip>
#include <smlib>

#pragma semicolon 1
#pragma newdecls  required

public Plugin myinfo = 
{
	name = "IP Bans Syncer",
	author = "AdRiAnIlloO",
	description = "Syncs native SRCDS IP bans with a SQL database",
	version = "1.4"
}

#define DATABASE_CONFIG_NAME "ip_bans"

#define IP_COMMAND_SLOT_WARNING(%1) "[SM] Please, specify an IP address to %s (slot indices not allowed)", #%1

#define MAX_IP_SIZE           16
#define SQL_MAX_QUERY_SIZE    2048
#define MAX_COUNTRY_CODE_SIZE 4
#define MAX_COUNTRY_NAME_SIZE 46

#define SQLITE_CURRENT_DATE_EXPRESSION  "DATETIME('NOW')"
#define SQLITE_EXPIRE_DATE_TO_TIMESTAMP "STRFTIME('%s', expireDate) + 0"
#define MYSQL_CURRENT_DATE_EXPRESSION   "NOW()"
#define MYSQL_EXPIRE_DATE_TO_TIMESTAMP  "UNIX_TIMESTAMP(expireDate)"

char gGeoIPCountryCodes[][MAX_COUNTRY_CODE_SIZE] =
{
	"AP", "EU", "AND", "ARE", "AFG", "ATG", "AIA", "ALB", "ARM", "ANT",
	"AGO", "AQ", "ARG", "ASM", "AUT", "AUS", "ABW", "AZE", "BIH", "BRB",
	"BGD", "BEL", "BFA", "BGR", "BHR", "BDI", "BEN", "BMU", "BRN", "BOL",
	"BRA", "BHS", "BTN", "BV", "BWA", "BLR", "BLZ", "CAN", "CC", "COD",
	"CAF", "COG", "CHE", "CIV", "COK", "CHL", "CMR", "CHN", "COL", "CRI",
	"CUB", "CPV", "CX", "CYP", "CZE", "DEU", "DJI", "DNK", "DMA", "DOM",
	"DZA", "ECU", "EST", "EGY", "ESH", "ERI", "ESP", "ETH", "FIN", "FJI",
	"FLK", "FSM", "FRO", "FRA", "FX", "GAB", "GBR", "GRD", "GEO", "GUF",
	"GHA", "GIB", "GRL", "GMB", "GIN", "GLP", "GNQ", "GRC", "GS", "GTM",
	"GUM", "GNB", "GUY", "HKG", "HM", "HND", "HRV", "HTI", "HUN", "IDN",
	"IRL", "ISR", "IND", "IO", "IRQ", "IRN", "ISL", "ITA", "JAM", "JOR",
	"JPN", "KEN", "KGZ", "KHM", "KIR", "COM", "KNA", "PRK", "KOR", "KWT",
	"CYM", "KAZ", "LAO", "LBN", "LCA", "LIE", "LKA", "LBR", "LSO", "LTU",
	"LUX", "LVA", "LBY", "MAR", "MCO", "MDA", "MDG", "MHL", "MKD", "MLI",
	"MMR", "MNG", "MAC", "MNP", "MTQ", "MRT", "MSR", "MLT", "MUS", "MDV",
	"MWI", "MEX", "MYS", "MOZ", "NAM", "NCL", "NER", "NFK", "NGA", "NIC",
	"NLD", "NOR", "NPL", "NRU", "NIU", "NZL", "OMN", "PAN", "PER", "PYF",
	"PNG", "PHL", "PAK", "POL", "SPM", "PCN", "PRI", "PSE", "PRT", "PLW",
	"PRY", "QAT", "REU", "ROU", "RUS", "RWA", "SAU", "SLB", "SYC", "SDN",
	"SWE", "SGP", "SHN", "SVN", "SJM", "SVK", "SLE", "SMR", "SEN", "SOM",
	"SUR", "STP", "SLV", "SYR", "SWZ", "TCA", "TCD", "TF", "TGO", "THA",
	"TJK", "TKL", "TKM", "TUN", "TON", "TLS", "TUR", "TTO", "TUV", "TWN",
	"TZA", "UKR", "UGA", "UM", "USA", "URY", "UZB", "VAT", "VCT", "VEN",
	"VGB", "VIR", "VNM", "VUT", "WLF", "WSM", "YEM", "YT", "SRB", "ZAF",
	"ZMB", "MNE", "ZWE", "A1", "A2", "O1", "ALA", "GGY", "IMN", "JEY",
	"BLM", "MAF"
};

Database gDatabase;

public void OnPluginStart()
{
	AddIPBanListener();
	AddCommandListener(CmdUnbanIP, "removeip");
}

void AddIPBanListener()
{
	AddCommandListener(CmdBanIP, "addip");
	AddCommandListener(CmdBanIP, "banip");
}

Action CmdBanIP(int client, const char[] command, int argsCount)
{
	char time[INT_MAX_DIGITS + 1], ip[MAX_IP_SIZE], query[SQL_MAX_QUERY_SIZE], country[MAX_COUNTRY_NAME_SIZE],
		countryCode[sizeof(gGeoIPCountryCodes[])], sqlCountryCode[sizeof(countryCode) * 2 + 1] = "NULL";
	GetCmdArg(1, time, sizeof(time));

	if (GetCmdArg(2, ip, sizeof(ip)) > 0)
	{
		int minutes = StringToInt(time);

		if (IPToLong(ip) == 0)
		{
			ReplyToCommand(client, IP_COMMAND_SLOT_WARNING(ban));
			return Plugin_Handled;
		}
		else if (gDatabase != null)
		{
			if (GeoipCode3(ip, countryCode))
			{
				gDatabase.Format(sqlCountryCode, sizeof(sqlCountryCode), "'%s'", countryCode);
			}

			bool isSQLite = IsDatabaseSQLite();
			int len = gDatabase.Format(query, sizeof(query),
				"INSERT INTO IPBan (ip, country, creationDate, expireDate) VALUES ('%s', %!s, ", ip, sqlCountryCode),
				expireTimestamp = (minutes > 0) ? GetTime() + minutes * 60 : 0;

			if (isSQLite)
			{
				gDatabase.Format(query[len], sizeof(query) - len, SQLITE_CURRENT_DATE_EXPRESSION
					... ", DATETIME(%i, 'UNIXEPOCH')) ON CONFLICT (ip) DO UPDATE SET country = excluded.country,"
					... " creationDate = excluded.creationDate, expireDate = excluded.expireDate;", expireTimestamp);
			}
			else
			{
				gDatabase.Format(query[len], sizeof(query) - len, MYSQL_CURRENT_DATE_EXPRESSION
					... ", FROM_UNIXTIME(%i)) ON DUPLICATE KEY UPDATE country = VALUES (country),"
					... " creationDate = VALUES (creationDate), expireDate = VALUES (expireDate);", expireTimestamp);
			}

			gDatabase.Query(OnQueryCompleted, query);
		}

		GeoipCountry(ip, country, sizeof(country));
		PrintToServer("[SM] Banned IP '%s' from %s for %i minute/s", ip, country, minutes);
	}

	return Plugin_Continue;
}

Action CmdUnbanIP(int client, const char[] command, int argsCount)
{
	char ip[MAX_IP_SIZE], query[SQL_MAX_QUERY_SIZE];

	if (GetCmdArg(1, ip, sizeof(ip)) > 0)
	{
		if (IPToLong(ip) == 0)
		{
			ReplyToCommand(client, IP_COMMAND_SLOT_WARNING(unban));
			return Plugin_Handled;
		}
		else if (gDatabase != null)
		{
			gDatabase.Format(query, sizeof(query), "DELETE FROM IPBan WHERE ip = '%s';", ip);
			gDatabase.Query(OnQueryCompleted, query);
		}
	}

	return Plugin_Continue;
}

public void OnMapStart()
{
	Database.Connect(OnDatabaseConnectFinished, SQL_CheckConfig(DATABASE_CONFIG_NAME)
		? DATABASE_CONFIG_NAME : "default");
}

public void OnMapEnd()
{
	delete gDatabase;
	gDatabase = null;
}

bool IsDatabaseSQLite()
{
	char driver[8];
	gDatabase.Driver.GetIdentifier(driver, sizeof(driver));
	return StrEqual(driver, "sqlite");
}

void OnDatabaseConnectFinished(Database database, const char[] error, any data)
{
	if (database == null)
	{
		LogError(error);
		return;
	}

	PrintToServer("[IP Bans] Successfully connected to database using specified parameters");
	gDatabase = database;
	char query[SQL_MAX_QUERY_SIZE], separator[3];
	bool isSQLite = IsDatabaseSQLite();
	int len = gDatabase.Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS IPBan"
		... " (id INTEGER %s PRIMARY KEY NOT NULL, ip VARCHAR (%i) UNIQUE NOT NULL, country ",
		isSQLite ? NULL_STRING : "AUTO_INCREMENT", MAX_IP_SIZE - 1);

	if (isSQLite)
	{
		len += gDatabase.Format(query[len], sizeof(query) - len, "VARCHAR (%i", sizeof(gGeoIPCountryCodes[]) - 1);
	}
	else
	{
		len += strcopy(query[len], sizeof(query) - len, "ENUM (");

		for (int i; i < sizeof(gGeoIPCountryCodes); separator = ", ", ++i)
		{
			len += gDatabase.Format(query[len], sizeof(query) - len, "%s'%s'", separator, gGeoIPCountryCodes[i]);
		}
	}

	strcopy(query[len], sizeof(query) - len, "), creationDate DATETIME, expireDate DATETIME);");
	database.Query(OnQueryCompleted, query);
	len = strcopy(query, sizeof(query), "DELETE FROM IPBan WHERE ");

	if (isSQLite)
	{
		gDatabase.Format(query[len], sizeof(query) - len, "%s > 0 AND %s >= expireDate;",
			SQLITE_EXPIRE_DATE_TO_TIMESTAMP, SQLITE_CURRENT_DATE_EXPRESSION);
	}
	else
	{
		gDatabase.Format(query[len], sizeof(query) - len, "%s > 0 AND %s >= expireDate;",
			MYSQL_EXPIRE_DATE_TO_TIMESTAMP, MYSQL_CURRENT_DATE_EXPRESSION);
	}

	database.Query(OnQueryCompleted, query);
	gDatabase.Format(query, sizeof(query), "SELECT ip, %s AS expireTimestamp FROM IPBan WHERE ip != '';",
		isSQLite ? SQLITE_EXPIRE_DATE_TO_TIMESTAMP : MYSQL_EXPIRE_DATE_TO_TIMESTAMP);
	database.Query(OnIPBansLoaded, query);
	ServerCommand("exec banned_ip");
}

void OnIPBansLoaded(Database database, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError(error);
		return;
	}

	RemoveCommandListener(CmdBanIP, "addip");
	RemoveCommandListener(CmdBanIP, "banip");

	while (results.FetchRow())
	{
		char ip[MAX_IP_SIZE];
		SQL_FetchStringByName(results, "ip", ip, sizeof(ip));
		int expireTimestamp = SQL_FetchIntByName(results, "expireTimestamp"), timeLeft;

		if (expireTimestamp < 1 || (timeLeft = (expireTimestamp - GetTime()) / 60) > 0)
		{
			ServerCommand("addip %i %s", timeLeft, ip);
			ServerExecute();
		}
	}

	AddIPBanListener();
}

void OnQueryCompleted(Database database, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError(error);
	}
}
