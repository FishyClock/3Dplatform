/****************************************************************************

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

***************************************************************************/

class FCW_Platform : PathFollower abstract
{
	Default
	{
		//Some editor keys for Ultimate Doom Builder.
		//For more info:
		//https://zdoom.org/wiki/Editor_keys
		//https://zdoom.org/wiki/Making_configurable_actors_in_DECORATE

		//$Arg3 Platform Options
		//$Arg3Type 12
		//Yes, this enum definition has to be on one line
		//$Arg3Enum {1 = "Use point roll"; 2 = "Don't clip against geometry and other platforms"; 4 = "Travel/Hold time in tics (not octics)"; 8 = "Travel/Hold time in seconds (not octics)"; 16 = "Start active";}
		//$Arg3Tooltip Flags 4 and 8 are mutually exclusive.\n(4 takes precedence over 8.)

		//$Arg4 Crush Damage
		//$Arg4Tooltip The damage is applied once per 4 tics.

		ClearFlags;
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
		//Args unique to "FCW_Platform"
		ARG_PLAT_OPTIONS = 3,
		ARG_PLAT_CRUSHDMG = 4,

		//Options/bit flags unique to "FCW_Platform"
		OPT_PLAT_ROLL = 1,
		OPT_PLAT_IGNOREGEO = 2,
		OPT_PLAT_TIMEINTICS = 4,
		OPT_PLAT_TIMEINSECS = 8,
		OPT_PLAT_STARTACTIVE = 16,

		//"PathFollower" args (that we check)
		ARG_FOLL_OPTIONS = 2,

		//"PathFollower" options/bit flags (that we check)
		OPT_FOLL_LINEAR = 1,
		OPT_FOLL_ANGLE = 2,
		OPT_FOLL_PITCH = 4,
		OPT_FOLL_FACEMOVE = 8,

		//"InterpolationPoint" args (that we check)
		ARG_NODE_TRAVELTIME = 1,
		ARG_NODE_HOLDTIME = 2,
	};

	vector3 oldPos;
	double oldAngle;
	double oldPitch;
	double oldRoll;
	double timeAdvance;
	bool bPlatBlocked; //Only useful for ACS. (See utility functions below.)
	bool bPlatInMove; //No collision between a platform and its riders during said platform's move.
	Array<Actor> riders;
	InterpolationPoint firstNode;
	InterpolationPoint firstPrevNode;

	//Unlike other PathFollower classes, our interpolations are done with
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
		timeAdvance = 0.;
		bPlatBlocked = false;
		bPlatInMove = false;
		firstNode = null;
		firstPrevNode = null;
		pCurr = pPrev = pNext = pNextNext = (0., 0., 0.);
		pCurrAngs = pPrevAngs = pNextAngs = pNextNextAngs = (0., 0., 0.);
	}

	//============================
	// PostBeginPlay (override)
	//============================
	override void PostBeginPlay ()
	{
		Super.PostBeginPlay();
		riders.Clear();

		//PathFollower stores its first acquired node in 'target'
		//and the "previous" node in 'lastEnemy'.
		//But that's unsafe because getting shot makes the platform
		//switch targets which is a problem if it gets activated
		//multiple times.
		firstNode = InterpolationPoint(target);
		firstPrevNode = InterpolationPoint(lastEnemy);

		if ((args[ARG_PLAT_OPTIONS] & OPT_PLAT_STARTACTIVE) != 0)
			Activate(self);
	}

	//============================
	// CanCollideWith (override)
	//============================
	override bool CanCollideWith(Actor other, bool passive)
	{
		if ((args[ARG_PLAT_OPTIONS] & OPT_PLAT_IGNOREGEO) != 0 && other is "FCW_Platform")
			return false;

		if (bPlatInMove && riders.Find(other) < riders.Size())
			return false;

		return true;
	}

	//============================
	// HasMoved
	//============================
	private bool HasMoved ()
	{
		return (pos != oldPos || angle != oldAngle || pitch != oldPitch || roll != oldRoll);
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

		int crushDamage = args[ARG_PLAT_CRUSHDMG];
		if (crushDamage <= 0 || (level.mapTime & 3) != 0)
			return;

		let oldZ = pushed.pos.z;
		pushed.AddZ(pushForce.z);
		bool fits = pushed.CheckMove(pushed.Vec2Offset(pushForce.x, pushForce.y));
		pushed.SetZ(oldZ);

		if (!fits)
		{
			int doneDamage = pushed.DamageMobj(null, null, crushDamage, 'Crush');
			pushed.TraceBleed((doneDamage > 0) ? doneDamage : crushDamage, self);
		}
	}

	//============================
	// UpdateTimeAdvance
	//============================
	private void UpdateTimeAdvance (int newTime)
	{
		int flags = args[ARG_PLAT_OPTIONS];
		if ((flags & OPT_PLAT_TIMEINTICS) != 0)
			timeAdvance = 1. / max(1, newTime); //Interpret 'newTime' as tics

		else if ((flags & OPT_PLAT_TIMEINSECS) != 0)
			timeAdvance = 1. / (max(1, newTime) * TICRATE); //Interpret 'newTime' as seconds

		else
			timeAdvance = 8. / (max(1, newTime) * TICRATE); //Interpret 'newTime' as octics
	}

	//============================
	// UpdateHoldTime
	//============================
	private void UpdateHoldTime (int newTime)
	{
		int flags = args[ARG_PLAT_OPTIONS];
		if ((flags & OPT_PLAT_TIMEINTICS) != 0)
			holdTime = level.mapTime + newTime; //Interpret 'newTime' as tics

		else if ((flags & OPT_PLAT_TIMEINSECS) != 0)
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
			pPrev = pos + level.Vec3Diff(pos, prevNode.pos); //Make it portal aware
			pPrevAngs = (
				Normalize180(prevNode.angle),
				Normalize180(prevNode.pitch),
				Normalize180(prevNode.roll));
		}
		if (currNode != null)
		{
			pCurr = pos + level.Vec3Diff(pos, currNode.pos); //Ditto
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
				pNext = pos + level.Vec3Diff(pos, currNode.next.pos); //Ditto
				pNextAngs = pCurrAngs + (
				DeltaAngle(pCurrAngs.x, currNode.next.angle),
				DeltaAngle(pCurrAngs.y, currNode.next.pitch),
				DeltaAngle(pCurrAngs.z, currNode.next.roll));

				if (currNode.next.next != null)
				{
					pNextNext = pos + level.Vec3Diff(pos, currNode.next.next.pos); //Ditto
					pNextNextAngs = pNextAngs + (
					DeltaAngle(pNextAngs.x, currNode.next.next.angle),
					DeltaAngle(pNextAngs.y, currNode.next.next.pitch),
					DeltaAngle(pNextAngs.z, currNode.next.next.roll));
				}
			}
		}
	}

	//============================
	// GetNewRiders
	//============================
	private bool GetNewRiders (bool ignoreObs, bool getAll)
	{
		//In addition to fetching riders, this is where corpses get crushed, too. (Items won't get destroyed.)
		//Returns false if blocked by actors.

		double top = pos.z + height;
		Array<Actor> miscResults; //The actors on top of the riders (We'll move those, too)
		Array<Actor> onTopOfMe;
		Array<FCW_Platform> otherPlats;

		//Call Grind() after we're done iterating because destroying
		//actors during iteration can mess up the iterator.
		Array<Actor> corpses;

		//Three things to do here when iterating:
		//1) Gather eligible riders.
		//2) Push obstacles (actors) out of the way, potentially inflicting "crush" damage if they can't be moved.
		//3) If said obstacles are corpses, grind them.
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

			//Check XY
			double blockDist = radius + mo.radius;
			if (abs(it.position.x - mo.pos.x) < blockDist && abs(it.position.y - mo.pos.y) < blockDist)
			{
				//'getAll' makes anything above our 'top' legit
				if (mo.pos.z >= top && (getAll || mo.pos.z <= top + 1.)) //On top of us?
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
						//Could 'mo' ride us, too?
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
									PushObstacle(mo, level.Vec3Diff(oldPos, pos));
							}
							if (!ignoreObs)
							{
								for (int i = 0; i < corpses.Size(); ++i)
									corpses[i].Grind(false);
								bPlatBlocked = true;
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

		//Do NOT take other platforms' riders!
		for (int iPlat = 0; iPlat < otherPlats.Size(); ++iPlat)
		{
			let plat = otherPlats[iPlat];
			for (int i = 0; i < onTopOfMe.Size(); ++i)
			{
				if (plat.riders.Find(onTopOfMe[i]) < plat.riders.Size())
					onTopOfMe.Delete(i--);
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
	private bool MoveRiders (bool ignoreObs)
	{
		//Returns false if a blocked rider would block the platform's movement

		//Do nothing if platform hasn't moved
		if (!HasMoved())
			return true;

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
		{
			//We're making the assumption that all
			//of them are in the blockmap at this point.
			//If that's somehow not the case then
			//don't touch them.
			let mo = riders[i];
			if (mo.bNoBlockmap)
				riders.Delete(i--);
			else
				mo.A_ChangeLinkFlags(removeFromBmap);
		}

		if (riders.Size() == 0)
			return true; //No riders? Nothing to do

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
			moNewPos = mo.pos + level.Vec3Diff(mo.pos, moNewPos);

			//Handle z discrepancy
			if (moNewPos.z < top && moNewPos.z + mo.height >= top)
				moNewPos.z = top;

			let moOldNoDropoff = mo.bNoDropoff;
			mo.bNoDropoff = false;
			mo.SetZ(moNewPos.z);
			bool moved = mo.TryMove(moNewPos.xy, 1);

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
				mo.SetZ(moOldPos.z);

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
					bPlatBlocked = true;
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
	private bool HandleOldRiders ()
	{
		//The main purpose of this is to keep walkers away from platform's edge.
		//The AI's native handling of trying not to fall off of other actors
		//just isn't good enough.
		//Returns true if it called GetNewRiders().

		bool didSearch = false;
		bool hasMoved = (bPlatBlocked || HasMoved());
		vector2 pushForce = (0., 0.);
		bool piPush = ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_PITCH) != 0);
		bool roPush = ((args[ARG_PLAT_OPTIONS] & OPT_PLAT_ROLL) != 0);

		//If we're not moving and we interpolate our pitch/roll,
		//and our pitch/roll is currently steep, then push things off of us.
		if (!hasMoved && (level.mapTime & 7) == 0)
		{
			if ((piPush || roPush) && (level.mapTime & 31) == 0)
			{
				GetNewRiders(true, false); //Get something to push off
				didSearch = true;
			}
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

			//Delete entry in array if...
			//(Sanity checks)
			if (mo == null || mo.bDestroyed) //Rider got destroyed since last tic?
			{
				riders.Delete(i--);
				continue;
			}
			if (mo.bNoBlockmap) //Suddenly isn't in the blockmap?
			{
				riders.Delete(i--);
				continue;
			}
			if (!mo.bCanPass && !mo.bSpecial) //Suddenly can't be carried?
			{
				riders.Delete(i--);
				continue;
			}
			if (mo.bFloorHugger || mo.bCeilingHugger) //Has become a floor/ceiling hugger?
			{
				riders.Delete(i--);
				continue;
			}
			//(End of sanity checks)

			if (mo.pos.z < top - 1.) //Is below us or stuck in us?
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
				if (!hasMoved && !piPush && !roPush)
					riders.Delete(i--);
				continue;
			}
			if (mo.bDropoff || mo.bJumpDown) //Is supposed to fall off of tall drops or jump down?
			{
				if (!hasMoved && !piPush && !roPush)
					riders.Delete(i--);
				continue;
			}

			//See if we should keep it away from the edge
			if (mo.tics != 1 && mo.tics != 0)
				continue; //Don't bother if it's not about to change states

			if (piPush || roPush)
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

		return didSearch;
	}

	//============================
	// Activate (override)
	//============================
	override void Activate (Actor activator)
	{
		if (!bActive)
		{
			currNode = firstNode;
			prevNode = firstPrevNode;

			if (currNode != null)
			{
				NewNode(); //Interpolation specials get called here
				if (bDestroyed)
					return; //Abort if we got Thing_Remove()'d
				GetNewRiders(true, true);
				SetOrigin(currNode.pos, false);
				time = 0.;
				holdTime = 0;
				bJustStepped = true;
				bActive = true;
				SetInterpolationCoordinates();
				UpdateTimeAdvance(currNode.args[ARG_NODE_TRAVELTIME]);

				//Don't fling away any riders if the pitch/roll difference is too great
				bool faceMove = ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_FACEMOVE) != 0);
				if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_PITCH) != 0)
				{
					if (faceMove && currNode.next != null)
					{
						let savedAng = angle;
						A_Face(currNode.next, 0., 0.);
						angle = savedAng;
						oldPitch = pitch;
					}
					else
					{
						pitch = oldPitch = currNode.pitch;
					}
				}
				if ((args[ARG_PLAT_OPTIONS] & OPT_PLAT_ROLL) != 0)
					roll = oldRoll = (faceMove) ? 0. : currNode.roll;

				MoveRiders(true);
			}
		}
	}

	//============================
	// MaybeLerp
	//============================
	private double MaybeLerp (double p1, double p2)
	{
		return (p1 == p2) ? p1 : Lerp(p1, p2);
	}

	//============================
	// MaybeSplerp
	//============================
	private double MaybeSplerp (double p1, double p2, double p3, double p4)
	{
		return (p2 == p3) ? p2 : Splerp(p1, p2, p3, p4);
	}

	//============================
	// Interpolate (override)
	//============================
	override bool Interpolate ()
	{
		//A heavily modified version of the
		//original function from PathFollower.

		Vector3 dpos = (0., 0., 0.);

		if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_FACEMOVE) != 0 && time > 0)
			dpos = pos;

		vector3 newPos;
		if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_LINEAR) != 0)
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

		let oldPGroup = curSector.portalGroup;
		bPlatInMove = true; //Temporarily don't clip against riders
		SetZ(newPos.z);
		bool moved = TryMove(newPos.xy, 1); //We need TryMove() for portal crossing

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
				bPlatBlocked = true;
				mo.SetZ(moOldZ);
				self.SetZ(oldPos.z);
				PushObstacle(mo, level.Vec3Diff(oldPos, newPos));
				return false;
			}
		}
		bPlatInMove = false;
		if (!moved) //Blocked by geometry?
		{
			if ((args[ARG_PLAT_OPTIONS] & OPT_PLAT_IGNOREGEO) != 0)
			{
				SetOrigin(level.Vec3Offset(pos, newPos - pos), true);
			}
			else
			{
				bPlatBlocked = true;
				SetZ(oldPos.z);
				return false;
			}
		}

		if (curSector.portalGroup != oldPGroup && pos != newPos) //Crossed a portal?
		{
			//Offset the coordinates
			vector3 offset = pos - newPos;
			pPrev += offset;
			pCurr += offset;
			pNext += offset;
			pNextNext += offset;
			newPos = pos;
		}

		if ((args[ARG_FOLL_OPTIONS] & (OPT_FOLL_ANGLE | OPT_FOLL_PITCH)) != 0 ||
			(args[ARG_PLAT_OPTIONS] & OPT_PLAT_ROLL) != 0)
		{
			if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_FACEMOVE) != 0)
			{
				if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_LINEAR) != 0)
				{
					dpos.x = pNext.x - pCurr.x;
					dpos.y = pNext.y - pCurr.y;
					dpos.z = pNext.z - pCurr.z;
				}
				else if (time > 0.) //Spline
				{
					dpos = newPos - dpos;
				}
				else //Spline but with time == 0.
				{
					dpos = newPos;
					time += timeAdvance;
					newPos.x = MaybeSplerp(pPrev.x, pCurr.x, pNext.x, pNextNext.x);
					newPos.y = MaybeSplerp(pPrev.y, pCurr.y, pNext.y, pNextNext.y);
					newPos.z = MaybeSplerp(pPrev.z, pCurr.z, pNext.z, pNextNext.z);
					time -= timeAdvance;
					dpos = newPos - dpos;
				}

				//Adjust angle
				if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_ANGLE) != 0)
					angle = VectorAngle(dpos.x, dpos.y);

				//Adjust pitch
				if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_PITCH) != 0)
				{
					double dist = dpos.xy.Length();
					pitch = (dist != 0.) ? VectorAngle(dist, -dpos.z) : 0.;
				}
				//Adjust roll
				if ((args[ARG_PLAT_OPTIONS] & OPT_PLAT_ROLL) != 0)
					roll = 0.;
			}
			else
			{
				if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_LINEAR) != 0)
				{
					//Interpolate angle
					if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_ANGLE) != 0)
						angle = MaybeLerp(pCurrAngs.x, pNextAngs.x);

					//Interpolate pitch
					if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_PITCH) != 0)
						pitch = MaybeLerp(pCurrAngs.y, pNextAngs.y);

					//Interpolate roll
					if ((args[ARG_PLAT_OPTIONS] & OPT_PLAT_ROLL) != 0)
						roll = MaybeLerp(pCurrAngs.z, pNextAngs.z);
				}
				else //Spline
				{
					//Interpolate angle
					if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_ANGLE) != 0)
						angle = MaybeSplerp(pPrevAngs.x, pCurrAngs.x, pNextAngs.x, pNextNextAngs.x);

					//Interpolate pitch
					if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_PITCH) != 0)
						pitch = MaybeSplerp(pPrevAngs.y, pCurrAngs.y, pNextAngs.y, pNextNextAngs.y);

					//Interpolate roll
					if ((args[ARG_PLAT_OPTIONS] & OPT_PLAT_ROLL) != 0)
						roll = MaybeSplerp(pPrevAngs.z, pCurrAngs.z, pNextAngs.z, pNextNextAngs.z);
				}
			}
		}
		return true;
	}

	//============================
	// Tick (override)
	//============================
	override void Tick ()
	{
		//Advance states (PathFollower doesn't do this)
		if (tics != -1 && --tics <= 0)
		{
			if (!SetState(curState.nextState))
				return; //Freed itself
		}

		bool searched = HandleOldRiders();
		bPlatBlocked = false;
		oldPos = pos;
		oldAngle = angle;
		oldPitch = pitch;
		oldRoll = roll;

		if (!bActive)
			return;

		if (bJustStepped)
		{
			bJustStepped = false;
			if (currNode != null)
				UpdateHoldTime(currNode.args[ARG_NODE_HOLDTIME]);
		}

		if (holdTime > level.mapTime)
			return;

		if ((!searched && !GetNewRiders(false, false)) || !Interpolate())
			return;

		if (!MoveRiders(false))
		{
			SetOrigin(oldPos, true);
			angle = oldAngle;
			pitch = oldPitch;
			roll = oldRoll;
			return;
		}

		time += timeAdvance;
		if (time > 1.)
		{
			time -= 1.;
			bJustStepped = true;
			prevNode = currNode;
			if (currNode != null)
				currNode = currNode.next;

			if (currNode != null)
			{
				NewNode(); //Interpolation specials get called here
				if (bDestroyed)
					return; //Abort if we got Thing_Remove()'d
				UpdateTimeAdvance(currNode.args[ARG_NODE_TRAVELTIME]);
				if (pos != currNode.pos)
				{
					oldPos = pos;
					oldAngle = angle;
					oldPitch = pitch;
					oldRoll = roll;
					SetOrigin(currNode.pos, false);
					MoveRiders(true);
				}
				SetInterpolationCoordinates();
			}

			if (currNode == null || currNode.next == null)
				Deactivate(self);
			else if ((args[ARG_FOLL_OPTIONS] & OPT_FOLL_LINEAR) == 0 && currNode.next.next == null)
				Deactivate(self);
		}
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
			plat.currNode = null;
			plat.prevNode = null;
			plat.pPrev = plat.pCurr = plat.pos;
			plat.pNext = plat.pNextNext = plat.Vec3Offset(offX, offY, offZ);
			plat.pPrevAngs = plat.pCurrAngs = (
				Normalize180(plat.angle),
				Normalize180(plat.pitch),
				Normalize180(plat.roll));
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (offAng, offPi, offRo);
			plat.time = 0.;
			plat.holdTime = 0;
			plat.UpdateTimeAdvance(newTime);
			plat.bActive = true;
		}
	}

	//============================
	// MoveTo (ACS utility)
	//============================
	static void MoveTo (int platTid, double newX, double newY, double newZ, int newTime, double offAng = 0., double offPi = 0., double offRo = 0.)
	{
		vector3 newPos = (newX, newY, newZ);
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while ((plat = FCW_Platform(it.Next())) != null)
		{
			plat.currNode = null;
			plat.prevNode = null;
			plat.pPrev = plat.pCurr = plat.pos;
			plat.pNext = plat.pNextNext = plat.pos + level.Vec3Diff(plat.pos, newPos); //Make it portal aware
			plat.pPrevAngs = plat.pCurrAngs = (
				Normalize180(plat.angle),
				Normalize180(plat.pitch),
				Normalize180(plat.roll));
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (offAng, offPi, offRo);
			plat.time = 0.;
			plat.holdTime = 0;
			plat.UpdateTimeAdvance(newTime);
			plat.bActive = true;
		}
	}

	//============================
	// MoveToSpot (ACS utility)
	//============================
	static void MoveToSpot (int platTid, int spotTid, int newTime)
	{
		let it = level.CreateActorIterator(spotTid);
		Actor spot = it.Next();
		if (spot == null)
			return; //No spot? Nothing to do

		it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while ((plat = FCW_Platform(it.Next())) != null)
		{
			plat.currNode = null;
			plat.prevNode = null;
			plat.pPrev = plat.pCurr = plat.pos;
			plat.pNext = plat.pNextNext = plat.pos + level.Vec3Diff(plat.pos, spot.pos); //Make it portal aware
			plat.pPrevAngs = plat.pCurrAngs = (
				Normalize180(plat.angle),
				Normalize180(plat.pitch),
				Normalize180(plat.roll));
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (
				DeltaAngle(plat.pCurrAngs.x, spot.angle),
				DeltaAngle(plat.pCurrAngs.y, spot.pitch),
				DeltaAngle(plat.pCurrAngs.z, spot.roll));
			plat.time = 0.;
			plat.holdTime = 0;
			plat.UpdateTimeAdvance(newTime);
			plat.bActive = true;
		}
	}

	//============================
	// IsMoving (ACS utility)
	//============================
	static bool IsMoving (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		let plat = FCW_Platform(it.Next());
		return (plat != null && plat.HasMoved());
	}

	//============================
	// IsBlocked (ACS utility)
	//============================
	static bool IsBlocked (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		let plat = FCW_Platform(it.Next());
		return (plat != null && plat.bPlatBlocked);
	}
}
