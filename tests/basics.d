/+ dub.sdl:
	name "test_basics"
	dependency "vibe-loxone" path="../"
	versions "VibeDefaultMain"
+/

import loxone.client;

import std.datetime;
import std.file;
import vibe.core.log;

static this()
{
	auto lox = new Loxone("192.168.0.79", "admin", "P!k*l!k$%1111");
	lox.connect();
	logInfo("Structure file modified on: %s", lox.getStructureTimestamp());
	logDiagnostic("Structure: %s", lox.getStructure());
	//auto img = lox.getFile!string("00000000-0000-0002-2000000000000000.svg");
	//logDiagnostic("Img: %s", img);
	//lox.enableStatusUpdates();
	//lox.addCommand(DateTime(2017, 6, 26, 12, 0, 0), "test", "0febd5d4-0398-e81f-ffffa7de92264b6a/on");
	//lox.addCommand(DateTime(2017, 6, 26, 13, 0, 0), "test", "0febd5d4-0398-e81f-ffffa7de92264b6a/off");
	//lox.removeCommand(DateTime(2017, 6, 26, 12, 0, 0), "test", "0febd5d4-0398-e81f-ffffa7de92264b6a/on");
	logDiagnostic("Sheduled commands: %s", lox.listCommands());
	logDiagnostic("Enumin: %s", lox.plcGetEnumIn());
	logDiagnostic("Enumout: %s", lox.plcGetEnumOut());
	logDiagnostic("Enumdev: %s", lox.plcGetEnumDev());
	logDiagnostic("State: %s", lox.plcGetState());
	logDiagnostic("Status: %s", lox.plcGetStatus());
	logDiagnostic("Identify: %s", lox.plcGetIdentify());
	//logDiagnostic("Changes: %s", lox.getChanges());
	logDiagnostic("CPU: %s", lox.sysGetCPU());
	logDiagnostic("Device state: %s", lox.getControlState("0febd5d4-0398-e81f-ffffa7de92264b6a"));
	lox.setControlValue("0febd5d4-0398-e81f-ffffa7de92264b6a", "off");
	lox.setControlValue("vin1", "on");
	lox.cfgGetMAC();
}
