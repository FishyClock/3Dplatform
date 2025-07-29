class DemoGenericPlat : FishyPlatform abstract
{
	States
	{
	Spawn:
		MODL A -1;
		Stop;
	}
}

//
//
//

class DemoCavePlat : DemoGenericPlat
{
	Default
	{
		Radius 32;
		Height 24;
	}
}

class DemoTwistingLift : FishyPlatform
{
	Default
	{
		Radius 64;
		Height 128;
	}

	States
	{
	Spawn:
		MODL A -1 NoDelay
		{
			if (user_snd_start == "")
				user_snd_start = "plats/pt1_strt";
			if (user_snd_stop == "")
				user_snd_stop = "plats/pt1_stop";
			if (user_snd_blocked == "")
				user_snd_blocked = "plats/pt1_stop";
		}
		Stop;
	}
}

class DemoSpinningSegment1 : DemoGenericPlat
{
	Default
	{
		Radius 40;
		Height 136;
	}
}

class DemoSpinningSegment2 : DemoGenericPlat
{
	Default
	{
		Radius 32;
		Height 128;
	}
}

class DemoSlidingFloor : FishyPlatform
{
	Default
	{
		Radius 32;
		Height 16;
	}

	States
	{
	Spawn:
		MODL A -1 NoDelay
		{
			if (user_snd_move == "")
				user_snd_move = "plats/pt1_mid";
			if (user_snd_stop == "")
				user_snd_stop = "plats/pt1_stop";
			if (user_snd_blocked == "")
				user_snd_blocked = "plats/pt1_stop";
		}
		Stop;
	}
}

class DemoWobblyMeatFloor : FishyPlatform
{
	Default
	{
		Radius 96;
		Height 248;
	}

	States
	{
	Spawn:
		MODL A random(40, 70); //Eyes open.
		MODL B random(3, 15);  //Eyes closed.
		Loop;
	}
}

class DemoWobblyMeatFloorNoEyes : DemoGenericPlat
{
	Default
	{
		Radius 96;
		Height 248;
	}
}

class DemoFirebluSegment : DemoGenericPlat
{
	Default
	{
		Radius 30;
		Height 16;
	}
}

class DemoFirebluSegmentTiny : DemoGenericPlat
{
	Default
	{
		Scale 0.2;
		Radius 6;
		Height 3.2;
	}
}

class DemoDiabolicalCube : FishyPlatform //This one isn't a model user. Oooh!
{
	Default
	{
		Radius 32;
		Height 24;
		+FORCEXYBILLBOARD;
	}

	States
	{
	Spawn:
		BOSF ABCD 5;
		Loop;
	}
}
