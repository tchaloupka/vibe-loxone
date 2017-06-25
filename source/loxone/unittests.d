module loxone.unittests;

import loxone.api;
import std.uuid;

@safe unittest
{
	import vibe.data.json;

	auto msg = `{"LL": { "control": "jdev/sys/getkey", "value": "30303641374345423239383736344132413937384246453733433843303145443843313636384339", "Code": "200"}}`;
	auto res = deserializeJson!LXResponse(msg);
	assert (res.control == "jdev/sys/getkey");
	assert (res.value == "30303641374345423239383736344132413937384246453733433843303145443843313636384339");
}

@safe unittest
{
	auto uuid = parseUUID("0feba4b8-03d3-0708-ffff2611f5ca7ad1");
	assert(uuid.toString() == "0feba4b8-03d3-0708-ffff-2611f5ca7ad1");
}

@safe unittest
{
	auto uuid = parseUUID("15b1e8e1-7f52-11e2-b92fa7de92264b6a");
	assert(uuid == UUID("15b1e8e1-7f52-11e2-b92f-a7de92264b6a"));
}

@safe unittest
{
	import std.stdio;
	auto uuid = parseUUID("15b1e8e1-7f52-11e2b92fa7de92264b6a");
	writeln(uuid.getString);
	assert(uuid.getString == "15b1e8e1-7f52-11e2-b92fa7de92264b6a");
}
