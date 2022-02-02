class TESTMooPlatform : FCW_Platform
{
	Default
	{
		Radius 64;
		Height 32;
	}

	States
	{
	Spawn:
		MODL A -1;
		Stop;
	}
}

class TESTFloaty : FCW_Platform
{
	Default
	{
		Radius 32;
		Height 80;
	}

	States
	{
	Spawn:
		MODL A -1;
		Stop;
	}
}

class TESTFlyingDoor : FCW_Platform
{
	Default
	{
		Radius 64;
		Height 8;
	}

	States
	{
	Spawn:
		MODL A -1;
		Stop;
	}
}
