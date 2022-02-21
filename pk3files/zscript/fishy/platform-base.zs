/******************************************************************************

 MIT License

 Copyright (c) 2022 FishyClockwork

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.

******************************************************************************/

class FCW_Platform : Actor abstract
{
	Default
	{
		//Some editor keys for Ultimate Doom Builder.
		//For more info:
		//https://zdoom.org/wiki/Editor_keys
		//https://zdoom.org/wiki/Making_configurable_actors_in_DECORATE

		//$Arg0 Target
		//$Arg0Type 14
		//$Arg0Tooltip Must be a interpolation point (path) or another platform (to mirror movement).\nNOTE: You can't have two platforms mirroring each other.

		//$Arg1 Options
		//$Arg1Type 12
		//Yes, this enum definition has to be on one line
		//$Arg1Enum {1 = "Linear path"; 2 = "Use target angle"; 4 = "Use target pitch"; 8 = "Use target roll"; 16 = "Face movement direction"; 32 = "Don't clip against geometry and other platforms"; 64 = "Travel/Hold time in tics (not octics)"; 128 = "Travel/Hold time in seconds (not octics)"; 256 = "Start active";}
		//$Arg1Tooltip Flag 64 takes precedence over flag 128.\nNOTE: When mirroring another platform, only flags 2, 4, 8 and 32 have any effect.

		//$Arg2 Crush Damage
		//$Arg2Tooltip The damage is applied once per 4 tics.

		+ACTLIKEBRIDGE;
		+NOGRAVITY;
		+CANPASS;
		+SOLID;
		+SHOOTABLE; //Block hitscan attacks

		//These are needed because we're shootable
		+NODAMAGE;
		+NOBLOOD;
		+DONTTHRUST;
		+NOTAUTOAIMED;
	}
}

//Ultimate Doom Builder doesn't need to read the rest
//$GZDB_SKIP

extend class FCW_Platform
{
	enum ArgValues
	{
		ARG_TARGET		= 0,
		ARG_OPTIONS		= 1,
		ARG_CRUSHDMG	= 2,

		OPTFLAG_LINEAR			= 1,
		OPTFLAG_ANGLE			= 2,
		OPTFLAG_PITCH			= 4,
		OPTFLAG_ROLL			= 8,
		OPTFLAG_FACEMOVE		= 16,
		OPTFLAG_IGNOREGEO		= 32,
		OPTFLAG_TIMEINTICS		= 64,
		OPTFLAG_TIMEINSECS		= 128,
		OPTFLAG_STARTACTIVE		= 256,

		//"InterpolationPoint" args (that we check)
		NODEARG_TRAVELTIME	= 1,
		NODEARG_HOLDTIME	= 2,
	};

	vector3 oldPos;
	double oldAngle;
	double oldPitch;
	double oldRoll;
	double time, timeFrac;
	int holdTime;
	bool bJustStepped;
	bool bPlatBlocked; //Only useful for ACS. (See utility functions below.)
	bool bPlatInMove; //No collision between a platform and its riders during said platform's move.
	InterpolationPoint currNode, firstNode;
	InterpolationPoint prevNode, firstPrevNode;
	Array<Actor> riders;
	Array<FCW_Platform> mirrors;
	FCW_Platform platMaster; //Mirrors have most of their thinking done by the platform they mirror (IE their master)

	//Unlike PathFollower classes, our interpolations are done with
	//vector3 coordinates rather than checking InterpolationPoint positions.
	//This is done for 2 reasons:
	//1) Making it portal aware.
	//2) Can be arbitrarily set through ACS (See utility functions below).
	vector3 pCurr, pPrev, pNext, pNextNext; //Positions in the world.
	vector3 pCurrAngs, pPrevAngs, pNextAngs, pNextNextAngs; //X = angle, Y = pitch, Z = roll.

	//============================
	// BeginPlay (override)
	//============================
	override void BeginPlay ()
	{
		Super.BeginPlay();
		oldPos = pos;
		oldAngle = angle;
		oldPitch = pitch;
		oldRoll = roll;
		time = timeFrac = 0.;
		holdTime = 0;
		bJustStepped = false;
		bPlatBlocked = false;
		bPlatInMove = false;
		currNode = firstNode = null;
		prevNode = firstPrevNode = null;
		riders.Clear();
		mirrors.Clear();
		platMaster = null;

		pCurr = pPrev = pNext = pNextNext = (0., 0., 0.);
		pCurrAngs = pPrevAngs = pNextAngs = pNextNextAngs = (0., 0., 0.);
	}

	//============================
	// PostBeginPlay (override)
	//============================
	override void PostBeginPlay ()
	{
		bDormant = true;
		if (args[ARG_TARGET] == 0)
			return; //Print no warnings if we're not supposed to look for anything

		String prefix = "\ckPlatform class '" .. GetClassName() .. "' with tid " .. tid .. ":\nat position " .. pos .. ":\n";
		if (args[ARG_TARGET] == tid)
		{
			Console.Printf(prefix .. "Is targeting itself.");
			return;
		}

		let it = level.CreateActorIterator(args[ARG_TARGET]);
		Actor mo = it.Next();
		while (mo != null && !(mo is "InterpolationPoint") && !(mo is "FCW_Platform"))
			mo = it.Next();

		if (mo == null)
		{
			Console.Printf(prefix .. "Can't find suitable target with tid " .. args[ARG_TARGET] .. ".\nTarget must be a interpolation point (path) or another platform (to mirror movement).");
			return;
		}

		if (mo is "FCW_Platform")
		{
			platMaster = FCW_Platform(mo);
			platMaster.mirrors.Push(self);

			//Get going if it's active
			//and we ticked after it.
			if (platMaster.pos != platMaster.spawnPoint)
				MirrorMove(true);
			return;
		}
		firstNode = InterpolationPoint(mo);

		//Verify the path has enough nodes
		firstNode.FormChain();
		if ((args[ARG_OPTIONS] & OPTFLAG_LINEAR) != 0)
		{
			if (firstNode.next == null) //Linear path; need 2 nodes
			{
				Console.Printf(prefix .. "Path needs at least 2 nodes.");
				return;
			}
		}
		else //Spline path; need 4 nodes
		{
			if (firstNode.next == null ||
				firstNode.next.next == null ||
				firstNode.next.next.next == null)
			{
				Console.Printf(prefix .. "Path needs at least 4 nodes.");
				return;
			}

			//If the first node is in a loop, we can start there.
			//Otherwise, we need to start at the second node in the path.
			firstPrevNode = firstNode.ScanForLoop();
			if (firstPrevNode == null || firstPrevNode.next != firstNode)
			{
				firstPrevNode = firstNode;
				firstNode = firstNode.next;
			}
		}

		if ((args[ARG_OPTIONS] & OPTFLAG_STARTACTIVE) != 0)
			Activate(self);
	}

	//============================
	// CanCollideWith (override)
	//============================
	override bool CanCollideWith(Actor other, bool passive)
	{
		if ((args[ARG_OPTIONS] & OPTFLAG_IGNOREGEO) != 0 && other is "FCW_Platform")
			return false;

		if (bPlatInMove && riders.Find(other) < riders.Size())
			return false;

		return true;
	}

	//============================
	// CollisionFlagChecks
	//============================
	private bool CollisionFlagChecks (Actor a, Actor b)
	{
		if (a.bThruActors || b.bThruActors)
			return false;

		if (!a.bSolid || !b.bSolid)
			return false;

		if ((a.bAllowThruBits || b.bAllowThruBits) && (a.thruBits & b.thruBits) != 0)
			return false;

		if ((a.bThruSpecies || b.bThruSpecies) && a.GetSpecies() == b.GetSpecies())
			return false;

		return true;
	}

	//============================
	// CrushObstacle
	//============================
	private void CrushObstacle (Actor victim)
	{
		int crushDamage = args[ARG_CRUSHDMG];
		if (crushDamage <= 0 || (level.mapTime & 3) != 0) //Only crush every 4th tic to allow victim's pain sound to be heard
			return;

		int doneDamage = victim.DamageMobj(null, null, crushDamage, 'Crush');
		victim.TraceBleed((doneDamage > 0) ? doneDamage : crushDamage, self);
	}

	//============================
	// PushObstacle
	//============================
	private void PushObstacle (Actor pushed, vector3 pushForce)
	{
		if (pushForce.z != 0. && Distance2D(pushed) >= radius + pushed.radius) //Out of range?
			pushForce.z = 0.;

		if (pushForce == (0., 0., 0.))
			return;

		if (pos.xy != pushed.pos.xy && pushForce.xy != (0., 0.))
		{
			double delta = DeltaAngle(VectorAngle(pushForce.x, pushForce.y), AngleTo(pushed));
			if (delta > 90. || delta < -90.)
				pushForce.xy = RotateVector(pushForce.xy, delta); //Push away from platform's center
		}
		pushed.vel += pushForce;

		if (args[ARG_CRUSHDMG] <= 0)
			return;

		let oldZ = pushed.pos.z;
		pushed.AddZ(pushForce.z);
		bool fits = pushed.CheckMove(pushed.Vec2Offset(pushForce.x, pushForce.y));
		pushed.SetZ(oldZ);

		if (!fits)
			CrushObstacle(pushed);
	}

	//============================
	// SetTimeFraction
	//============================
	private void SetTimeFraction (int newTime)
	{
		int flags = args[ARG_OPTIONS];
		if ((flags & OPTFLAG_TIMEINTICS) != 0)
			timeFrac = 1. / max(1, newTime); //Interpret 'newTime' as tics

		else if ((flags & OPTFLAG_TIMEINSECS) != 0)
			timeFrac = 1. / (max(1, newTime) * TICRATE); //Interpret 'newTime' as seconds

		else
			timeFrac = 8. / (max(1, newTime) * TICRATE); //Interpret 'newTime' as octics
	}

	//============================
	// SetHoldTime
	//============================
	private void SetHoldTime (int newTime)
	{
		if (newTime <= 0)
			return;

		int flags = args[ARG_OPTIONS];
		if ((flags & OPTFLAG_TIMEINTICS) != 0)
			holdTime = level.mapTime + newTime; //Interpret 'newTime' as tics

		else if ((flags & OPTFLAG_TIMEINSECS) != 0)
			holdTime = level.mapTime + newTime * TICRATE; //Interpret 'newTime' as seconds

		else
			holdTime = level.mapTime + newTime * TICRATE / 8; //Interpret 'newTime' as octics
	}

	//============================
	// SetInterpolationCoordinates
	//============================
	private void SetInterpolationCoordinates ()
	{
		if (prevNode != null)
		{
			pPrev = pos + Vec3To(prevNode); //Make it portal aware
			pPrevAngs = (
				Normalize180(prevNode.angle),
				Normalize180(prevNode.pitch),
				Normalize180(prevNode.roll));
		}
		if (currNode != null)
		{
			pCurr = pos + Vec3To(currNode); //Ditto
			if (prevNode == null)
				pCurrAngs = (
				Normalize180(currNode.angle),
				Normalize180(currNode.pitch),
				Normalize180(currNode.roll));
			else
				pCurrAngs = pPrevAngs + (
				DeltaAngle(pPrevAngs.x, currNode.angle),
				DeltaAngle(pPrevAngs.y, currNode.pitch),
				DeltaAngle(pPrevAngs.z, currNode.roll));

			if (currNode.next != null)
			{
				pNext = pos + Vec3To(currNode.next); //Ditto
				pNextAngs = pCurrAngs + (
				DeltaAngle(pCurrAngs.x, currNode.next.angle),
				DeltaAngle(pCurrAngs.y, currNode.next.pitch),
				DeltaAngle(pCurrAngs.z, currNode.next.roll));

				if (currNode.next.next != null)
				{
					pNextNext = pos + Vec3To(currNode.next.next); //Ditto
					pNextNextAngs = pNextAngs + (
					DeltaAngle(pNextAngs.x, currNode.next.next.angle),
					DeltaAngle(pNextAngs.y, currNode.next.next.pitch),
					DeltaAngle(pNextAngs.z, currNode.next.next.roll));
				}
			}
		}
	}

	//============================
	// CheckMirrorEntries
	//============================
	private void CheckMirrorEntries ()
	{
		for (int i = 0; i < mirrors.Size(); ++i)
		{
			let m = mirrors[i];
			if (m == null || m.bDestroyed)
			{
				mirrors.Delete(i--);
				continue;
			}
			m.platMaster = self;
			m.CheckMirrorEntries();
		}
	}

	//============================
	// UpdateOldInfo
	//============================
	private void UpdateOldInfo ()
	{
		bPlatBlocked = false;
		oldPos = pos;
		oldAngle = angle;
		oldPitch = pitch;
		oldRoll = roll;
		for (int i = 0; i < mirrors.Size(); ++i)
			mirrors[i].UpdateOldInfo();
	}

	//============================
	// GetNewRiders
	//============================
	private bool GetNewRiders (bool ignoreObs, bool laxZCheck)
	{
		//In addition to fetching riders, this is where corpses get crushed, too. (Items won't get destroyed.)
		//Returns false if an actor is completely stuck inside platform.

		double top = pos.z + height;
		Array<Actor> miscResults; //The actors on top of the riders (We'll move those, too)
		Array<Actor> onTopOfMe;
		Array<FCW_Platform> otherPlats;

		//Call Grind() after we're done iterating because destroying
		//actors during iteration can mess up the iterator.
		Array<Actor> corpses;

		//Three things to do here when iterating:
		//1) Gather eligible riders.
		//2) Damage any non-platform actors that are stuck inside platform (and can't be placed on top of platform)
		//3) If said actors are corpses, "grind" them instead.

		//NOTE: Only one live actor can get damaged per tic and makes this function return false.
		//While all detected corpses will be grinded in one go and won't stop the gathering process.
		let it = BlockThingsIterator.Create(self);
		while (it.Next())
		{
			let mo = it.thing;
			if (mo == self)
				continue;

			//Due to how the engine handles actor-to-actor interactions
			//we can only carry things with the +CANPASS or the
			//+SPECIAL flag. Anything else will just fall through.
			//Even when we have +ACTLIKEBRIDGE.
			bool canCarry = (!(mo is "FCW_Platform") && //Platforms shouldn't carry other platforms.
				!mo.bFloorHugger && !mo.bCeilingHugger && //Don't bother with floor/ceiling huggers.
				(mo.bCanPass || mo.bSpecial));

			bool oldRider = (riders.Find(mo) < riders.Size());
			if (mo is "FCW_Platform")
				otherPlats.Push(FCW_Platform(mo));

			//Check XY overlap
			double blockDist = radius + mo.radius;
			if (abs(it.position.x - mo.pos.x) < blockDist && abs(it.position.y - mo.pos.y) < blockDist)
			{
				//'laxZCheck' makes anything above our 'top' legit
				if (mo.pos.z >= top && (laxZCheck || mo.pos.z <= top + 1.)) //On top of us?
				{
					if (canCarry && !oldRider)
						onTopOfMe.Push(mo);
					continue;
				}

				if (mo.pos.z + mo.height > pos.z && top > mo.pos.z) //Overlaps Z?
				{
					if (mo.bCorpse && !mo.bDontGib && mo.tics == -1) //Let dying actors finish their death sequence
					{
						if (!ignoreObs)
							corpses.Push(mo);
					}
					else if (CollisionFlagChecks(self, mo) && self.CanCollideWith(mo, false) && mo.CanCollideWith(self, true))
					{
						//Try to correct 'mo' Z so it can ride us, too.
						//But only if its 'maxStepHeight' allows it.
						bool blocked = true;
						let moOldZ = mo.pos.z;
						if (!(mo is "FCW_Platform") && top - mo.pos.z <= mo.maxStepHeight)
						{
							mo.SetZ(top);
							blocked = !mo.CheckMove(mo.pos.xy);
						}
						if (blocked)
						{
							if (!(mo is "FCW_Platform"))
							{
								mo.SetZ(moOldZ);
								if (!ignoreObs)
									CrushObstacle(mo);
							}
							if (!ignoreObs)
							{
								for (int i = 0; i < corpses.Size(); ++i)
									corpses[i].Grind(false);
								return false; //Try again in the next tic
							}
							else continue;
						}
						if (canCarry && !oldRider)
							onTopOfMe.Push(mo);
					}
					continue;
				}
			}

			if (canCarry && !oldRider)
				miscResults.Push(mo); //We'll compare this later against the riders
		}

		for (int i = 0; i < corpses.Size(); ++i)
			corpses[i].Grind(false);

		//Do NOT take other platforms' riders! Unless...
		for (int iPlat = 0; iPlat < otherPlats.Size(); ++iPlat)
		{
			let plat = otherPlats[iPlat];
			bool myTopIsHigher = (top > plat.pos.z + plat.height);

			for (int i = 0; i < onTopOfMe.Size(); ++i)
			{
				let index = plat.riders.Find(onTopOfMe[i]);
				if (index < plat.riders.Size())
				{
					if (myTopIsHigher)
						plat.riders.Delete(index); //Steal it!
					else
						onTopOfMe.Delete(i--);
				}
			}
			for (int i = 0; i < miscResults.Size(); ++i)
			{
				if (plat.riders.Find(miscResults[i]) < plat.riders.Size())
					miscResults.Delete(i--);
			}
		}
		riders.Append(onTopOfMe);

		//Now figure out which of the misc actors are on top of/stuck inside
		//established riders.
		for (int i = 0; i < riders.Size(); ++i)
		{
			let mo = riders[i];
			double moTop = mo.pos.z + mo.height + 1.;

			for (int iOther = 0; iOther < miscResults.Size(); ++iOther)
			{
				let otherMo = miscResults[iOther];

				if (moTop > otherMo.pos.z && otherMo.pos.z + otherMo.height > mo.pos.z && //Is 'otherMo' on top of or stuck inside 'mo'?
					mo.Distance2D(otherMo) < mo.radius + otherMo.radius) //Within XY range?
				{
					miscResults.Delete(iOther--); //Don't compare this one against other riders anymore
					riders.Push(otherMo);
				}
			}
		}
		return true;
	}

	//============================
	// MoveRiders
	//============================
	private bool MoveRiders (bool ignoreObs, bool teleMove)
	{
		//Returns false if a blocked rider would block the platform's movement

		if (riders.Size() == 0)
			return true; //No riders? Nothing to do

		//The goal is to move all riders as if they were one entity.
		//The only things that should block any of them are
		//non-riders and geometry.
		//The exception is if a rider can't fit at its new position
		//in which case it will be "solid" for the others.
		//
		//To accomplish this each of them will temporarily
		//be removed from the blockmap.

		int addToBmap = 0, removeFromBmap = 1;

		for (int i = 0; i < riders.Size(); ++i)
			riders[i].A_ChangeLinkFlags(removeFromBmap);

		//Move our riders (platform rotation is taken into account)
		double top = pos.z + height;
		double delta = DeltaAngle(oldAngle, angle);
		double piDelta = DeltaAngle(oldPitch, pitch)*2;
		double roDelta = DeltaAngle(oldRoll, roll)*2;

		vector2 piAndRoOffset = (cos(angle)*piDelta, sin(angle)*piDelta) + //Front/back
			(cos(angle-90.)*roDelta, sin(angle-90.)*roDelta); //Right/left

		Array<double> preMovePos; //Sadly we can't have a vector2/3 dyn array
		for (int i = 0; i < riders.Size(); ++i)
		{
			let mo = riders[i];
			let moOldPos = mo.pos;

			vector3 offset = level.Vec3Diff(oldPos, mo.pos);
			if (delta != 0.)
				offset.xy = RotateVector(offset.xy, delta);
			offset.xy += piAndRoOffset;
			vector3 moNewPos = level.Vec3Offset(pos, offset);

			//TryMove() has its own internal handling of portals which is
			//a problem if 'moNewPos' is already through a portal from the platform's
			//perspective. What it wants/needs is a offsetted position from 'mo' assuming
			//no portals have been crossed yet.
			if (!teleMove)
				moNewPos = mo.pos + level.Vec3Diff(mo.pos, moNewPos);

			//Handle z discrepancy
			if (moNewPos.z < top && moNewPos.z + mo.height >= top)
				moNewPos.z = top;

			let moOldNoDropoff = mo.bNoDropoff;
			mo.bNoDropoff = false;
			bool moved;
			if (teleMove)
			{
				mo.SetOrigin(moNewPos, false);
				moved = mo.CheckMove(moNewPos.xy);
			}
			else
			{
				mo.SetZ(moNewPos.z);
				moved = mo.TryMove(moNewPos.xy, 1);
			}

			//Take into account riders getting Thing_Remove()'d
			//when they activate lines.
			if (mo == null || mo.bDestroyed)
			{
				riders.Delete(i--);
				continue;
			}
			mo.bNoDropoff = moOldNoDropoff;

			if (moved)
			{
				//Only remember the old position if 'mo' was moved.
				//(Else we delete the 'riders' entry containing 'mo', see below.)
				preMovePos.Push(moOldPos.x);
				preMovePos.Push(moOldPos.y);
				preMovePos.Push(moOldPos.z);
			}
			else
			{
				mo.SetOrigin(moOldPos, true);

				//This rider will be 'solid' for the others
				mo.A_ChangeLinkFlags(addToBmap);
				riders.Delete(i--);

				//See if it would block the platform
				double moTop = mo.pos.z + mo.height;
				bool blocked = ( !ignoreObs && CollisionFlagChecks(mo, self) &&
					moTop > self.pos.z && top > mo.pos.z && //Overlaps Z?
					mo.Distance2D(self) < mo.radius + self.radius && //Within XY range?
					mo.CanCollideWith(self, false) && self.CanCollideWith(mo, true) );

				//See if the ones we moved already will collide with this one
				//and if yes, move them back to their old positions.
				//(If the platform's "blocked" then move everyone back unconditionally.)
				for (int iOther = 0; iOther <= i; ++iOther)
				{
					let otherMo = riders[iOther];
					if ( !blocked && ( !CollisionFlagChecks(otherMo, mo) ||
						moTop <= otherMo.pos.z || otherMo.pos.z + otherMo.height <= mo.pos.z || //No Z overlap?
						otherMo.Distance2D(mo) >= otherMo.radius + mo.radius || //Out of XY range?
						!otherMo.CanCollideWith(mo, false) || !mo.CanCollideWith(otherMo, true) ) )
					{
						continue;
					}

					//Put 'otherMo' back at its old position
					vector3 otherOldPos = (preMovePos[iOther*3], preMovePos[(iOther*3)+1], preMovePos[(iOther*3)+2]);
					otherMo.SetOrigin(otherOldPos, true);

					otherMo.A_ChangeLinkFlags(addToBmap);
					preMovePos.Delete(iOther*3, 3);
					riders.Delete(iOther--);
					i--;
				}

				if (blocked)
				{
					PushObstacle(mo, level.Vec3Diff(oldPos, pos));
					for (i = 0; i < riders.Size(); ++i)
						riders[i].A_ChangeLinkFlags(addToBmap); //Handle those that didn't get the chance to move
					return false;
				}
			}
		}

		//Anyone left in the 'riders' array has moved successfully.
		//Change their angles.
		for (int i = 0; i < riders.Size(); ++i)
		{
			let mo = riders[i];
			mo.A_ChangeLinkFlags(addToBmap);
			if (delta != 0.)
				mo.angle = Normalize180(mo.angle + delta);
		}
		return true;
	}

	//============================
	// HandleOldRiders
	//============================
	private void HandleOldRiders ()
	{
		//The main purpose of this is to keep walkers away from platform's edge.
		//The AI's native handling of trying not to fall off of other actors
		//just isn't good enough.

		bool hasMoved = (bPlatBlocked ||
			pos != oldPos ||
			angle != oldAngle ||
			pitch != oldPitch ||
			roll != oldRoll);
		vector2 pushForce = (0., 0.);
		bool piPush = ((args[ARG_OPTIONS] & OPTFLAG_PITCH) != 0);
		bool roPush = ((args[ARG_OPTIONS] & OPTFLAG_ROLL) != 0);

		//If we're not moving and we interpolate our pitch/roll,
		//and our pitch/roll is currently steep, then push things off of us.
		if (!hasMoved && (level.mapTime & 7) == 0) //Push is applied once per 8 tics.
		{
			if ((piPush || roPush) && (level.mapTime & 63) == 0)
				GetNewRiders(true, false); //Get something to push off

			if (piPush && riders.Size() > 0)
			{
				pitch = Normalize180(pitch);
				if (abs(pitch) >= 45. && abs(pitch) <= 135.)
				{
					vector2 newPush = (cos(angle), sin(angle)); //Push front or back
					pushForce += ((pitch > 0. && pitch < 90.) || pitch < -90.) ? newPush : -newPush;
				}
			}
			if (roPush && riders.Size() > 0)
			{
				roll = Normalize180(roll);
				if (abs(roll) >= 45. && abs(roll) <= 135.)
				{
					vector2 newPush = (cos(angle-90.), sin(angle-90.)); //Push right or left
					pushForce += ((roll > 0. && roll < 90.) || roll < -90.) ? newPush : -newPush;
				}
			}
		}

		double top = pos.z + height;

		for (int i = 0; i < riders.Size(); ++i)
		{
			let mo = riders[i];
			if (mo == null || mo.bDestroyed ||
				mo.bNoBlockmap ||
				mo.bFloorHugger || mo.bCeilingHugger ||
				(!mo.bCanPass && !mo.bSpecial))
			{
				riders.Delete(i--);
				continue;
			}

			//'floorZ' can be the top of a 3D floor that's right below an actor.
			if (mo.pos.z < top - 1. || mo.floorZ > top + 1.) //Is below us or stuck in us or there's a 3D floor between us?
			{
				riders.Delete(i--);
				continue;
			}

			double dist = Distance2D(mo);
			if (dist >= radius + mo.radius) //Is out of XY range?
			{
				riders.Delete(i--);
				continue;
			}

			mo.vel.xy += pushForce;
			if (!mo.bIsMonster || mo.bNoGravity || mo.bFloat || mo.speed == 0) //Is not a walking monster?
			{
				if (!hasMoved && pushForce == (0., 0.))
					riders.Delete(i--);
				continue;
			}
			if (mo.bDropoff || mo.bJumpDown) //Is supposed to fall off of tall drops or jump down?
			{
				if (!hasMoved && pushForce == (0., 0.))
					riders.Delete(i--);
				continue;
			}

			//See if we should keep it away from the edge
			if (mo.tics != 1 && mo.tics != 0)
				continue; //Don't bother if it's not about to change states

			if (pushForce != (0., 0.))
				continue; //Not if we're pushing it

			if (mo.pos.z > top + 1.)
				continue; //Not exactly on top of us

			if (dist < radius - mo.speed)
				continue; //Not close to platform's edge

			if (mo.pos.z - mo.curSector.NextLowestFloorAt(mo.pos.x, mo.pos.y, mo.pos.z) <= mo.maxDropoffHeight)
				continue; //Monster is close to the ground (which includes 3D floors) so let it walk off

			//Make your bog-standard idTech1 AI
			//that uses A_Chase() or A_Wander()
			//walk towards the platform's center.
			//NOTE: This isn't fool proof if there
			//are multiple riders moving on the
			//same platform at the same time.
			mo.moveDir = int(mo.AngleTo(self) / 45) & 7;
			if (mo.moveCount < 1)
				mo.moveCount = 1;
		}

		for (int i = 0; i < mirrors.Size(); ++i)
			mirrors[i].HandleOldRiders();
	}

	//============================
	// MaybeLerp
	//============================
	private double MaybeLerp (double p1, double p2)
	{
		return (p1 == p2) ? p1 : (p1 + time * (p2 - p1));
	}

	//============================
	// MaybeSplerp
	//============================
	private double MaybeSplerp (double p1, double p2, double p3, double p4)
	{
		if (p2 == p3)
			return p2;

		// This was copy-pasted from PathFollower's Splerp() function
		//
		// Interpolate between p2 and p3 along a Catmull-Rom spline
		// http://research.microsoft.com/~hollasch/cgindex/curves/catmull-rom.html
		//
		// NOTE: the above link doesn't seem to work so here's an alternative. -FishyClockwork
		// https://en.wikipedia.org/wiki/Cubic_Hermite_spline#Catmull%E2%80%93Rom_spline
		double t = time;
		double res = 2*p2;
		res += (p3 - p1) * time;
		t *= time;
		res += (2*p1 - 5*p2 + 4*p3 - p4) * t;
		t *= time;
		res += (3*p2 - 3*p3 + p4 - p1) * t;
		return 0.5 * res;
	}

	//============================
	// PlatTryMove
	//============================
	private bool PlatTryMove (vector3 newPos)
	{
		if (pos == newPos)
			return true;

		bPlatInMove = true; //Temporarily don't clip against riders
		SetZ(newPos.z);
		bool moved = TryMove(newPos.xy, 1);

		if (!moved && blockingMobj != null && !(blockingMobj is "FCW_Platform"))
		{
			let mo = blockingMobj;
			let moOldZ = mo.pos.z;
			let moNewZ = newPos.z + self.height;

			//Try to set the obstacle on top of us if its 'maxStepHeight' allows it
			if (moNewZ > moOldZ && moNewZ - moOldZ <= mo.maxStepHeight)
			{
				mo.SetZ(moNewZ);
				if (mo.CheckMove(mo.pos.xy)) //Obstacle fits at new Z even before we moved?
					moved = TryMove(newPos.xy, 1); //Try one more time
			}

			if (!moved) //Blocked by actor that isn't a platform?
			{
				bPlatInMove = false;
				mo.SetZ(moOldZ);
				self.SetZ(oldPos.z);
				PushObstacle(mo, level.Vec3Diff(oldPos, newPos));
				return false;
			}
		}
		bPlatInMove = false;

		if (!moved) //Blocked by geometry or another platform?
		{
			if ((args[ARG_OPTIONS] & OPTFLAG_IGNOREGEO) != 0)
			{
				SetOrigin(level.Vec3Offset(pos, newPos - pos), true);
			}
			else
			{
				SetZ(oldPos.z);
				return false;
			}
		}

		return true;
	}

	//============================
	// Interpolate
	//============================
	private bool Interpolate ()
	{
		//A heavily modified version of the
		//original function from PathFollower.

		Vector3 dpos = (0., 0., 0.);
		if ((args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) != 0 && time > 0.)
			dpos = pos;

		vector3 newPos;
		if ((args[ARG_OPTIONS] & OPTFLAG_LINEAR) != 0)
		{
			newPos.x = MaybeLerp(pCurr.x, pNext.x);
			newPos.y = MaybeLerp(pCurr.y, pNext.y);
			newPos.z = MaybeLerp(pCurr.z, pNext.z);
		}
		else //Spline
		{
			newPos.x = MaybeSplerp(pPrev.x, pCurr.x, pNext.x, pNextNext.x);
			newPos.y = MaybeSplerp(pPrev.y, pCurr.y, pNext.y, pNextNext.y);
			newPos.z = MaybeSplerp(pPrev.z, pCurr.z, pNext.z, pNextNext.z);
		}

		//Do a blockmap search once per tic if we're in motion.
		//Otherwise, do (at most) two searches per 64 tics (almost 2 seconds).
		//The first non-motion search can happen in HandleOldRiders().
		//The second non-motion search will happen here 32 tics after the first one.
		if (newPos != pos || ((level.mapTime + 32) & 63) == 0)
		{
			if (!GetNewRiders(false, false))
				return false;
		}

		let oldPGroup = curSector.portalGroup;
		if (!PlatTryMove(newPos))
			return false;

		if ((args[ARG_OPTIONS] & (OPTFLAG_ANGLE | OPTFLAG_PITCH | OPTFLAG_ROLL)) != 0)
		{
			if ((args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) != 0)
			{
				if ((args[ARG_OPTIONS] & OPTFLAG_LINEAR) != 0)
				{
					dpos = pNext - pCurr;
				}
				else if (time > 0.) //Spline
				{
					dpos = newPos - dpos;
				}
				else if ((args[ARG_OPTIONS] & (OPTFLAG_ANGLE | OPTFLAG_PITCH)) != 0)
				{	//Spline but with time == 0.
					dpos = newPos;
					time = timeFrac;
					newPos.x = MaybeSplerp(pPrev.x, pCurr.x, pNext.x, pNextNext.x);
					newPos.y = MaybeSplerp(pPrev.y, pCurr.y, pNext.y, pNextNext.y);
					newPos.z = MaybeSplerp(pPrev.z, pCurr.z, pNext.z, pNextNext.z);
					time = 0.;
					dpos = newPos - dpos;
					newPos -= dpos;
				}

				//Adjust angle
				if ((args[ARG_OPTIONS] & OPTFLAG_ANGLE) != 0)
					angle = VectorAngle(dpos.x, dpos.y);

				//Adjust pitch
				if ((args[ARG_OPTIONS] & OPTFLAG_PITCH) != 0)
				{
					double dist = dpos.xy.Length();
					pitch = (dist != 0.) ? VectorAngle(dist, -dpos.z) : 0.;
				}
				//Adjust roll
				if ((args[ARG_OPTIONS] & OPTFLAG_ROLL) != 0)
					roll = 0.;
			}
			else
			{
				if ((args[ARG_OPTIONS] & OPTFLAG_LINEAR) != 0)
				{
					//Interpolate angle
					if ((args[ARG_OPTIONS] & OPTFLAG_ANGLE) != 0)
						angle = MaybeLerp(pCurrAngs.x, pNextAngs.x);

					//Interpolate pitch
					if ((args[ARG_OPTIONS] & OPTFLAG_PITCH) != 0)
						pitch = MaybeLerp(pCurrAngs.y, pNextAngs.y);

					//Interpolate roll
					if ((args[ARG_OPTIONS] & OPTFLAG_ROLL) != 0)
						roll = MaybeLerp(pCurrAngs.z, pNextAngs.z);
				}
				else //Spline
				{
					//Interpolate angle
					if ((args[ARG_OPTIONS] & OPTFLAG_ANGLE) != 0)
						angle = MaybeSplerp(pPrevAngs.x, pCurrAngs.x, pNextAngs.x, pNextNextAngs.x);

					//Interpolate pitch
					if ((args[ARG_OPTIONS] & OPTFLAG_PITCH) != 0)
						pitch = MaybeSplerp(pPrevAngs.y, pCurrAngs.y, pNextAngs.y, pNextNextAngs.y);

					//Interpolate roll
					if ((args[ARG_OPTIONS] & OPTFLAG_ROLL) != 0)
						roll = MaybeSplerp(pPrevAngs.z, pCurrAngs.z, pNextAngs.z, pNextNextAngs.z);
				}
			}
		}

		if (!MoveRiders(false, false))
		{
			SetOrigin(oldPos, true);
			angle = oldAngle;
			pitch = oldPitch;
			roll = oldRoll;
			return false;
		}

		if (curSector.portalGroup != oldPGroup && pos != newPos) //Crossed a portal?
		{
			//Offset the coordinates
			vector3 offset = pos - newPos;
			pPrev += offset;
			pCurr += offset;
			pNext += offset;
			pNextNext += offset;
		}

		for (int i = 0; i < mirrors.Size(); ++i)
		{
			//If one of our mirrors is blocked, pretend
			//we're blocked too. (Our move won't be cancelled.)
			if (!mirrors[i].MirrorMove(false))
				return false;
		}
		return true;
	}

	//============================
	// MirrorMove
	//============================
	private bool MirrorMove (bool teleMove)
	{
		//The way we mirror movement is by getting the offset going
		//from the mirror's current position to its spawn position
		//and using that to get a offsetted position from
		//our own spawn position.
		//So we pretty much always go in the opposite direction
		//using our spawn position as a reference point.
		vector3 offset = level.Vec3Diff(platMaster.pos, platMaster.spawnPoint);
		vector3 newPos = level.Vec3Offset(spawnPoint, offset);

		//Do a blockmap search once per tic if we're in motion.
		//Otherwise, do (at most) two searches per 64 tics (almost 2 seconds).
		//The first non-motion search can happen in HandleOldRiders().
		//The second non-motion search will happen here 32 tics after the first one.
		if (newPos != pos || ((level.mapTime + 32) & 63) == 0)
		{
			if (!GetNewRiders(false, false))
				return false;
		}

		if (teleMove)
		{
			SetOrigin(newPos, false);
		}
		else
		{
			newPos = pos + level.Vec3Diff(pos, newPos); //For TryMove()
			if (!PlatTryMove(newPos))
				return false;
		}

		if ((args[ARG_OPTIONS] & OPTFLAG_ANGLE) != 0)
		{
			//Same offset logic as position changing
			double delta = DeltaAngle(platMaster.angle, platMaster.spawnAngle);
			angle = Normalize180(spawnAngle + delta);
		}

		if ((args[ARG_OPTIONS] & OPTFLAG_PITCH) != 0)
			pitch = Normalize180(platMaster.pitch);

		if ((args[ARG_OPTIONS] & OPTFLAG_ROLL) != 0)
			roll = -Normalize180(platMaster.roll);

		if (!MoveRiders(teleMove, teleMove))
		{
			SetOrigin(oldPos, true);
			angle = oldAngle;
			pitch = oldPitch;
			roll = oldRoll;
			return false;
		}

		for (int i = 0; i < mirrors.Size(); ++i)
		{
			//If one of our mirrors is blocked, pretend
			//we're blocked too. (Our move won't be cancelled.)
			//Yes, mirrors can get mirrored, too.
			//(But they can't mirror each other.)
			if (!mirrors[i].MirrorMove(teleMove))
				return false;
		}
		return true;
	}

	//============================
	// CallNodeSpecials
	//============================
	private void CallNodeSpecials ()
	{
		let it = level.CreateActorIterator(currNode.tid, "InterpolationSpecial");
		Actor spec;

		//Precaution against Thing_Remove() shenanigans.
		//If a special holder gets removed/destroyed
		//during iteration then the iterator gets
		//messed up. Gather all specials before
		//calling them.
		Array<int> specList;
		while ((spec = it.Next()) != null)
		{
			if (spec.special == 0)
				continue;
			specList.Push(spec.special);
			for (int i = 0; i < 5; ++i)
				specList.Push(spec.args[i]);
		}

		for (int i = 0; i < specList.Size(); i += 6)
			level.ExecuteSpecial(specList[i], null, null, false, specList[i+1], specList[i+2], specList[i+3], specList[i+4], specList[i+5]);
	}

	//============================
	// Deactivate (override)
	//============================
	override void Deactivate (Actor activator)
	{
		bDormant = true;
	}

	//============================
	// Activate (override)
	//============================
	override void Activate (Actor activator)
	{
		if (bDormant)
		{
			currNode = firstNode;
			prevNode = firstPrevNode;

			if (currNode != null)
			{
				CallNodeSpecials();
				if (bDestroyed || currNode == null || currNode.bDestroyed)
					return; //Abort if we or the node got Thing_Remove()'d

				CheckMirrorEntries();
				GetNewRiders(true, true);
				UpdateOldInfo();
				SetOrigin(currNode.pos, false);
				time = 0.;
				holdTime = 0;
				bJustStepped = true;
				bDormant = false;
				SetInterpolationCoordinates();
				SetTimeFraction(currNode.args[NODEARG_TRAVELTIME]);

				//Don't fling away any riders if the pitch/roll difference is too great
				bool faceMove = ((args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) != 0);
				if ((args[ARG_OPTIONS] & OPTFLAG_PITCH) != 0)
				{
					if (faceMove && currNode.next != null)
					{
						vector3 dpos;
						if ((args[ARG_OPTIONS] & OPTFLAG_LINEAR) != 0)
						{
							dpos = Vec3To(currNode.next);
						}
						else //Spline
						{
							time = timeFrac;
							dpos.x = MaybeSplerp(pPrev.x, pCurr.x, pNext.x, pNextNext.x);
							dpos.y = MaybeSplerp(pPrev.y, pCurr.y, pNext.y, pNextNext.y);
							dpos.z = MaybeSplerp(pPrev.z, pCurr.z, pNext.z, pNextNext.z);
							time = 0.;
							dpos -= pos; //It's an offset
						}
						double dist = dpos.xy.Length();
						pitch = oldPitch = (dist != 0.) ? VectorAngle(dist, -dpos.z) : 0.;
					}
					else
					{
						pitch = oldPitch = currNode.pitch;
					}
				}
				if ((args[ARG_OPTIONS] & OPTFLAG_ROLL) != 0)
					roll = oldRoll = (faceMove) ? 0. : currNode.roll;

				MoveRiders(true, true);
				for (int i = 0; i < mirrors.Size(); ++i)
					mirrors[i].MirrorMove(true);
			}
		}
	}

	//============================
	// Tick (override)
	//============================
	override void Tick ()
	{
		//Advance states
		if (tics != -1 && --tics <= 0)
		{
			if (!SetState(curState.nextState))
				return; //Freed itself
		}

		//Sanity check - most of a mirror's thinking is done by its master
		if (platMaster != null)
		{
			let pMastIndex = platMaster.mirrors.Find(self);
			if (pMastIndex < platMaster.mirrors.Size())
			{
				//Because the way this is set up to work you
				//can't have two platforms mirroring each other.
				let myIndex = mirrors.Find(platMaster);
				if (myIndex < mirrors.Size())
				{
					Console.Printf("\ckPlatform class '" .. GetClassName() .. "' with tid " .. tid .. ":\nat position " .. pos .. ":\n" ..
					"and platform class '" .. platMaster.GetClassName() .. "' with tid " .. platMaster.tid .. ":\nat position " .. platMaster.pos .. ":\n" ..
					"are mirroring each other; Mirror info will be cleared for both.");

					mirrors.Delete(myIndex);
					platMaster.mirrors.Delete(pMastIndex);
					platMaster.platMaster = null;
				}
				else
				{
					return;
				}
			}
			platMaster = null;
		}

		CheckMirrorEntries();
		HandleOldRiders();
		UpdateOldInfo();

		if (bDormant)
			return;

		if (bJustStepped)
		{
			bJustStepped = false;
			if (currNode != null)
				SetHoldTime(currNode.args[NODEARG_HOLDTIME]);
		}

		if (holdTime > level.mapTime)
			return;

		if (!Interpolate())
		{
			bPlatBlocked = true;
			return;
		}

		time += timeFrac;
		if (time > 1.)
		{
			time -= 1.;
			bJustStepped = true;
			prevNode = currNode;
			if (currNode != null)
				currNode = currNode.next;

			if (currNode != null)
			{
				CallNodeSpecials();
				if (bDestroyed)
					return; //Abort if we got Thing_Remove()'d

				if (currNode == null || currNode.bDestroyed)
				{
					Deactivate(self);
					return; //Our node got Thing_Remove()'d
				}
				SetInterpolationCoordinates();
				SetTimeFraction(currNode.args[NODEARG_TRAVELTIME]);
			}

			if (currNode == null || currNode.next == null)
				Deactivate(self);
			else if ((args[ARG_OPTIONS] & OPTFLAG_LINEAR) == 0 && currNode.next.next == null)
				Deactivate(self);
		}
	}

	//============================
	// CommonACSSetup
	//============================
	private void CommonACSSetup (int newTime)
	{
		if (platMaster != null)
		{
			//Stop mirroring
			let index = platMaster.mirrors.Find(self);
			if (index < platMaster.mirrors.Size())
				platMaster.mirrors.Delete(index);
			platMaster = null;
		}
		currNode = null; //Deactivate when done moving
		prevNode = null;
		time = 0.;
		holdTime = 0;
		SetTimeFraction(newTime);
		bDormant = false;
		pPrev = pCurr = pos;
		pPrevAngs = pCurrAngs = (
			Normalize180(angle),
			Normalize180(pitch),
			Normalize180(roll));
	}

	//============================
	// Move (ACS utility)
	//============================
	static void Move (int platTid, double offX, double offY, double offZ, int newTime, double offAng = 0., double offPi = 0., double offRo = 0.)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while ((plat = FCW_Platform(it.Next())) != null)
		{
			plat.CommonACSSetup(newTime);
			plat.pNext = plat.pNextNext = plat.Vec3Offset(offX, offY, offZ);
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (offAng, offPi, offRo);
		}
	}

	//============================
	// MoveTo (ACS utility)
	//============================
	static void MoveTo (int platTid, double newX, double newY, double newZ, int newTime, double offAng = 0., double offPi = 0., double offRo = 0.)
	{
		//ACS itself has no 'vector3' variable type so it has to be 3 doubles (floats/fixed point numbers)
		vector3 newPos = (newX, newY, newZ);
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while ((plat = FCW_Platform(it.Next())) != null)
		{
			plat.CommonACSSetup(newTime);
			plat.pNext = plat.pNextNext = plat.pos + level.Vec3Diff(plat.pos, newPos); //Make it portal aware
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (offAng, offPi, offRo);
		}
	}

	//============================
	// MoveToSpot (ACS utility)
	//============================
	static void MoveToSpot (int platTid, int spotTid, int newTime)
	{
		//This is the only place you can make a platform use any actor as a travel destination
		let it = level.CreateActorIterator(spotTid);
		Actor spot = it.Next();
		if (spot == null)
			return; //No spot? Nothing to do

		it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while ((plat = FCW_Platform(it.Next())) != null)
		{
			plat.CommonACSSetup(newTime);
			plat.pNext = plat.pNextNext = plat.pos + plat.Vec3To(spot); //Make it portal aware
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (
				DeltaAngle(plat.pCurrAngs.x, spot.angle),
				DeltaAngle(plat.pCurrAngs.y, spot.pitch),
				DeltaAngle(plat.pCurrAngs.z, spot.roll));
		}
	}

	//============================
	// IsMoving (ACS utility)
	//============================
	static bool IsMoving (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		let plat = FCW_Platform(it.Next());
		if (plat == null)
			return false;
		if (plat.platMaster != null)
			plat = plat.platMaster;
		return (!plat.bDormant && (
			plat.pos != plat.oldPos ||
			plat.angle != plat.oldAngle ||
			plat.pitch != plat.oldPitch ||
			plat.roll != plat.oldRoll));
	}

	//============================
	// IsBlocked (ACS utility)
	//============================
	static bool IsBlocked (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		let plat = FCW_Platform(it.Next());
		if (plat == null)
			return false;
		if (plat.platMaster != null)
			plat = plat.platMaster;
		return (!plat.bDormant && plat.bPlatBlocked);
	}
}
