class TESTPlat : FCW_Platform abstract
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

class TESTMooPlatform : TESTPlat
{
	Default
	{
		Radius 64;
		Height 32;
	}
}

class TESTFloaty : TESTPlat
{
	Default
	{
		Radius 32;
		Height 80;
	}
}

class TESTFlyingDoor : TESTPlat
{
	Default
	{
		Radius 64;
		Height 8;
	}
}

class TESTSprite : TESTPlat
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

class TESTBlueishPlatform : TESTPlat
{
	Default
	{
		Radius 64;
		Height 16;
	}
}

class TESTPushCrate : TESTPlat
{
	Default
	{
		Radius 48;
		Height 80;
		+PUSHABLE;
		-NOGRAVITY;
		+FCW_Platform.CARRIABLE;
	}
}

class TESTTorchZombo : ZombieMan
{
	Default
	{
		//$Title Torch zombo!
	}

	override void PostBeginPlay ()
	{
		Super.PostBeginPlay();
		tracer = Spawn("ShortRedTorch", pos + (0, 0, height));
		tracer.bNoGravity = true;
		tracer.bSolid = false;
	}

	override void Tick ()
	{
		Super.Tick();

		if (InStateSequence(curState, seeState))
			TorchZomboRoutine();
	}

	void TorchZomboRoutine ()
	{
		if (tracer)
		{
			tracer.SetOrigin(pos + (0, 0, height), true);
			tracer.vel = (0, 0, 0);
		}

		if (!random[TorchZombo](0, 32))
		{
			Actor puff = Spawn("BulletPuff", pos + (0, 0, height));
			puff.vel.z = 8;
		}
	}

	override void Die (Actor source, Actor inflictor, int dmgflags, Name MeansOfDeath)
	{
		if (tracer && tracer is "ShortRedTorch")
			tracer.Destroy();

		Super.Die(source, inflictor, dmgflags, MeansOfDeath);
	}
}

extend class TESTPlat
{
	override void PassengerPostMove (Actor mo)
	{
		if (mo is "TESTTorchZombo")
			TESTTorchZombo(mo).TorchZomboRoutine();
	}
}
