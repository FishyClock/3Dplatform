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

class TESTSprite : FCW_Platform
{
	Default
	{
		Radius 64;
		Height 16;
		+ROLLSPRITE;
	}

	States
	{
	Spawn:
		TROO A -1 NoDelay //Test NoDelay
		{
			Actor indicator = Spawn("TESTSPritePitchIndicator", pos);
			indicator.tracer = self;
		}
		Stop;
	}
}

class TESTSPritePitchIndicator : Actor
{
	Default
	{
		+NOINTERACTION;
		+NOBLOCKMAP;
	}

	States
	{
	Spawn:
		APLS AAABBB 1
		{
			if (!tracer)
			{
				Destroy();
				return;
			}
			SetOrigin(tracer.Vec3Offset(cos(tracer.angle)*tracer.radius, sin(tracer.angle)*tracer.radius, sin(-tracer.pitch)*tracer.radius), true);
		}
		Loop;
	}
}

class TESTBlueishPlatform : FCW_Platform
{
	Default
	{
		Radius 64;
		Height 16;
	}

	States
	{
	Spawn:
		MODL A -1;
		Stop;
	}
}

class TESTPushCrate : FCW_Platform
{
	Default
	{
		Radius 48;
		Height 80;
		+PUSHABLE;
		-NOGRAVITY;
		+FCW_Platform.CARRIABLE;
	}

	States
	{
	Spawn:
		MODL A -1;
		Stop;
	}
}
