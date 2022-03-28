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
		Radius 24;
		Height 64;
		+ROLLSPRITE; //This is our indicator for roll changes
	}

	States
	{
	Spawn:
		BOSS A 5 NoDelay //Test NoDelay
		{
			Actor indicator = Spawn("TESTSPritePitchIndicator", pos);
			indicator.tracer = self;
		}
		Goto Baron+1;
	Baron:
		BOSS ABCD 5;
		BOSS A 0 A_Jump(64, "HK");
		Loop;
	HK:
		BOS2 ABCD 5;
		BOS2 A 0 A_Jump(64, "Baron");
		Loop;
	}
}

class TESTSPritePitchIndicator : Actor
{
	Default
	{
		+NOINTERACTION;
		+NOBLOCKMAP;
		+ROLLSPRITE;
	}

	States
	{
	Spawn:
		BAL7 AAAABBBB 1
		{
			if (!tracer)
			{
				Destroy();
				return;
			}
			SetOrigin(tracer.Vec3Offset(cos(tracer.angle)*64, sin(tracer.angle)*64, sin(-tracer.pitch)*64), true);
			angle = tracer.angle;
			roll = tracer.roll;
		}
		Loop;
	}
}