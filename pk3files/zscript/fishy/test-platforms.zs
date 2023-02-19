class TESTPlat : FishyPlatform abstract
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
			quat q = quat.FromAngles(tracer.angle, tracer.pitch, tracer.roll);
			vector3 offset = q * (tracer.radius, 0, 0);
			SetOrigin(level.Vec3Offset(tracer.pos, offset), true);
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
		+FishyPlatform.CARRIABLE;
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

	override bool CanCollideWith (Actor other, bool passive)
	{
		return (!tracer || tracer != other);
	}
}

//Example of how to deal with a unique class
extend class TESTPlat
{
	override void PassengerPreMove (Actor mo)
	{
		if (mo is "TESTTorchZombo" && mo.tracer)
			mo.tracer.bSolid = false;
	}

	override void PassengerPostMove (Actor mo, bool moved)
	{
		if (mo is "TESTTorchZombo")
		{
			if (moved)
				TESTTorchZombo(mo).TorchZomboRoutine();
			if (mo.tracer)
				mo.tracer.bSolid = true;
		}
	}
}

//Example enemy/shootable platform
class TESTNastyHeart : FishyPlatform
{
	Default
	{
		Health 300;
		Radius 30;
		Height 16;
		PainChance 200;
		SeeSound "caco/sight";
		PainSound "caco/pain";
		DeathSound "brain/pain";
		-NODAMAGE;
		-NOBLOOD;
		-NOTAUTOAIMED;
		+MISSILEMORE;
		+MISSILEEVENMORE;
		Obituary "%o succumbed to FIREBLU <3";
	}

	States
	{
	Spawn:
		MODL A 10 A_LookEx(fov: 360); //"Wake up" as soon as player is in sight
		Loop;
	See:
		MODL A 4
		{
			//For some reason CHF_DONTTURN doesn't actually stop turning *sigh*
			let ang = angle;
			A_Chase(flags: CHF_DONTMOVE|CHF_DONTTURN);
			angle = ang;
		}
		Loop;
	Missile:
		MODL A 5 A_SpawnProjectile("CacodemonBall", 0);
		MODL A 5
		{
			if(random[NastyHeart](1, 3) == 3) //One in three chance to shoot additional imp ball
				A_SpawnProjectile("DoomImpBall", 0);
		}
		Goto See;
	Pain:
		MODL A 10
		{
			A_StartSound(PainSound, CHAN_BODY, pitch: 1.0);
			A_StartSound(PainSound, CHAN_VOICE, pitch: 0.8);
		}
		Goto See;
	Death:
		TNT1 A 1
		{
			A_StopSound(CHAN_BODY);
			A_StartSound(DeathSound, CHAN_VOICE);

			//Shoot out 20 soul spheres
			double toAdd = 360.0 / 20;
			for (double i = 0.0; i < 360.0; i += toAdd)
			{
				let sphere = Spawn("Soulsphere", pos, ALLOW_REPLACE);
				if (sphere)
				{
					sphere.angle = i;
					sphere.VelFromAngle(15);
				}
			}
		}
		Stop;
	}
}
