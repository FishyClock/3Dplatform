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
		//All editor key definitions have to be on one line
		//or UDB can't parse them correctly. (Yes, even "Arg1Enum")
		//For more info:
		//https://zdoom.org/wiki/Editor_keys
		//https://zdoom.org/wiki/Making_configurable_actors_in_DECORATE

		//$Arg0 Interpolation Point
		//$Arg0Type 14
		//$Arg0Tooltip Must be 'Platform Interpolation Point' or GZDoom's 'Interpolation Point' class.\nWhichever is more convenient.\n'Interpolation Special' works with both.

		//$Arg1 Options
		//$Arg1Type 12
		//$Arg1Enum {1 = "Linear path / (Does nothing for non-origin group members)"; 2 = "Use point angle / Group move: Rotate angle / (ACS commands don't need this)"; 4 = "Use point pitch / Group move: Rotate pitch / (ACS commands don't need this)"; 8 = "Use point roll / Group move: Rotate roll / (ACS commands don't need this)"; 16 = "Face movement direction / (Does nothing for non-origin group members)"; 32 = "Don't clip against geometry and other platforms"; 64 = "Start active"; 128 = "Group move: Mirror group origin's movement"; 256 = "Add velocity to passengers when they jump away"; 512 = "Add velocity to passengers when stopping (and not blocked)"; 1024 = "Interpolation point is destination"; 2048 = "Resume path when activated again"; 4096 = "Always do 'crush damage' when pushing obstacles";}
		//$Arg1Tooltip 'Group move' affects movement imposed by the group origin.\nThe 'group origin' is the platform that other members move with and orbit around.\nActivating any group member will turn it into the group origin.

		//$Arg2 Platform(s) To Group With
		//$Arg2Type 14

		//$Arg3 Crush Damage
		//$Arg3Tooltip If an obstacle is pushed against a wall,\nthe damage is applied once per 4 tics.

		+INTERPOLATEANGLES;
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

class FCW_PlatformNode : InterpolationPoint
{
	Default
	{
		//$Title Platform Interpolation Point

		//$Arg0 Next Point
		//$Arg0Type 14

		//$Arg1 Travel Time

		//$Arg2 Hold Time

		//$Arg3 Travel Time Unit
		//$Arg3Type 11
		//$Arg3Enum {0 = "Octics"; 1 = "Tics"; 2 = "Seconds";}

		//$Arg4 Hold Time Unit
		//$Arg4Type 11
		//$Arg4Enum {0 = "Octics"; 1 = "Tics"; 2 = "Seconds";}
	}
}

//Ultimate Doom Builder doesn't need to read the rest
//$GZDB_SKIP

extend class FCW_PlatformNode
{
	void PNodeFormChain ()
	{
		// The relevant differences from InterpolationPoint's FormChain() are:
		// 1) The archaic tid/hi-tid lookup is gone.
		// 2) The tid to look for is on a different argument.
		// 3) The pitch isn't clamped.

		for (FCW_PlatformNode node = self; node; node = FCW_PlatformNode(node.next))
		{
			if (node.bVisited)
				return;
			node.bVisited = true;

			let it = level.CreateActorIterator(node.args[0], "FCW_PlatformNode");
			do
			{
				node.next = FCW_PlatformNode(it.Next());
			} while (node.next == node); //Don't link to self

			if (!node.next && node.args[0])
				Console.Printf("\ckPlatform interpolation point with tid " .. node.tid .. " at position " ..node.pos ..
				":\ncannot find next platform interpolation point with tid " .. node.args[0] .. ".");
		}
	}
}

class FCW_PlatformGroup play
{
	Array<FCW_Platform> members;
	FCW_Platform origin;	//Called so because every other member orbits around and follows this one.
							//Also, the "origin" does most of the thinking for the other members. See Tick().

	static FCW_PlatformGroup Create ()
	{
		let group = new("FCW_PlatformGroup");
		group.members.Clear();
		group.origin = null;
		return group;
	}

	void Add (FCW_Platform plat)
	{
		plat.group = self;
		if (members.Find(plat) >= members.Size())
			members.Push(plat);
	}

	FCW_Platform GetMember (int index)
	{
		//Handle invalid entries
		while (index < members.Size() && !members[index])
			members.Delete(index);

		if (index < members.Size())
		{
			members[index].group = self; //Ensure members point to the correct group
			return members[index];
		}
		return null;
	}

	void MergeWith (FCW_PlatformGroup otherGroup)
	{
		for (int i = 0; i < otherGroup.members.Size(); ++i)
		{
			let plat = otherGroup.GetMember(i);
			if (plat)
				Add(plat);
		}
	}
}

extend class FCW_Platform
{
	enum ArgValues
	{
		ARG_NODETID			= 0,
		ARG_OPTIONS			= 1,
		ARG_GROUPTID		= 2,
		ARG_CRUSHDMG		= 3,

		//For "ARG_OPTIONS"
		OPTFLAG_LINEAR			= 1,
		OPTFLAG_ANGLE			= 2,
		OPTFLAG_PITCH			= 4,
		OPTFLAG_ROLL			= 8,
		OPTFLAG_FACEMOVE		= 16,
		OPTFLAG_IGNOREGEO		= 32,
		OPTFLAG_STARTACTIVE		= 64,
		OPTFLAG_MIRROR			= 128,
		OPTFLAG_ADDVELJUMP		= 256,
		OPTFLAG_ADDVELSTOP		= 512,
		OPTFLAG_GOTONODE		= 1024,
		OPTFLAG_RESUMEPATH		= 2048,
		OPTFLAG_HURTFULPUSH		= 4096,

		//FCW_PlatformNode args that we check
		NODEARG_TRAVELTIME		= 1, //Also applies to InterpolationPoint
		NODEARG_HOLDTIME		= 2, //Ditto
		NODEARG_TRAVELTUNIT		= 3,
		NODEARG_HOLDTUNIT		= 4,

		//For FCW_PlatformNode's "NODEARG_TRAVELTUNIT" and "NODEARG_HOLDTUNIT"
		TIMEUNIT_OCTICS		= 0,
		TIMEUNIT_TICS		= 1,
		TIMEUNIT_SECS		= 2,
	};

	const TOP_EPSILON = 1.0;
	const ZS_EQUAL_EPSILON = 1.0 / 65536.0; //Because 'double.epsilon' is too small, we'll use 'EQUAL_EPSILON' from the source code
	const YES_BMAP = 0; //For A_ChangeLinkFlags()
	const NO_BMAP = 1;
	const EXTRA_SIZE = 20; //For line collision checking

	vector3 oldPos;
	double oldAngle;
	double oldPitch;
	double oldRoll;
	double spawnZ; //This is not the same as spawnPoint.z
	double spawnPitch;
	double spawnRoll;
	double time;
	double timeFrac;
	int holdTime;
	bool bActive;
	transient bool bPlatInMove; //No collision between a platform and its passengers during said platform's move.
	InterpolationPoint currNode, firstNode;
	InterpolationPoint prevNode, firstPrevNode;
	bool goToNode;
	Array<Actor> passengers;
	Array<Actor> stuckActors;
	FCW_PlatformGroup group;
	Line lastUPort;
	private FCW_Platform portTwin; //Helps with collision when dealing with unlinked line portals
	private bool bPortCopy;

	//Unlike PathFollower classes, our interpolations are done with
	//vector3 coordinates instead of checking InterpolationPoint positions.
	//This is done for 2 reasons:
	//1) Making it portal aware.
	//2) Can be arbitrarily set through ACS (See utility functions below).
	vector3 pCurr, pPrev, pNext, pNextNext; //Positions in the world.
	vector3 pCurrAngs, pPrevAngs, pNextAngs, pNextNextAngs; //X = angle, Y = pitch, Z = roll.

	States
	{
	//Portal twins that are invisible and aren't meant
	//to have fancy states/animations/etc.
	PortalCopy:
		TNT1 A -1;
		Stop;
	}

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
		spawnZ = pos.z;
		spawnPitch = pitch;
		spawnRoll = roll;
		time = 1.1;
		timeFrac = 0;
		holdTime = 0;
		bActive = false;
		bPlatInMove = false;
		currNode = firstNode = null;
		prevNode = firstPrevNode = null;
		goToNode = false;
		passengers.Clear();
		stuckActors.Clear();
		group = null;
		lastUPort = null;
		portTwin = null;
		bPortCopy = false;

		pCurr = pPrev = pNext = pNextNext = (0, 0, 0);
		pCurrAngs = pPrevAngs = pNextAngs = pNextNextAngs = (0, 0, 0);
	}

	//============================
	// PostBeginPlay (override)
	//============================
	override void PostBeginPlay ()
	{
		Super.PostBeginPlay();
		if (bPortCopy)
			return;

		String prefix = "\ckPlatform class '" .. GetClassName() .. "' with tid " .. tid .. " at position " .. pos .. ":\n";

		if (args[ARG_GROUPTID])
		{
			let it = level.CreateActorIterator(args[ARG_GROUPTID], "FCW_Platform");
			FCW_Platform plat;
			bool foundOne = false;
			while (plat = FCW_Platform(it.Next()))
			{
				if (plat != self)
					foundOne = true;

				if (plat.group) //Target is in its own group?
				{
					if (!group) //We don't have a group?
						plat.group.Add(self);
					else if (plat.group != group) //Both are in different groups?
						plat.group.MergeWith(group);
					//else - nothing happens because it's the same group or plat == self
				}
				else if (group) //We're in a group but target doesn't have a group?
				{
					group.Add(plat);
				}
				else if (plat != self) //Neither are in a group
				{
					let newGroup = FCW_PlatformGroup.Create();
					newGroup.Add(self);
					newGroup.Add(plat);
				}
			}

			if (!foundOne)
			{
				Console.Printf(prefix .. "Can't find platform(s) with tid " .. args[ARG_GROUPTID] .. " to group with.");
				prefix = "\ck";
			}
		}

		if (group && group.origin)
		{
			let ori = group.origin;
			if (ori.pos.xy != ori.spawnPoint.xy ||
				ori.pos.z != ori.spawnZ ||
				ori.angle != ori.spawnAngle ||
				ori.pitch != ori.spawnPitch ||
				ori.roll != ori.spawnRoll)
			{
				//If the group origin is already active then call MoveGroup() now.
				//This matters if the origin's first interpolation point has a defined hold time
				//because depending on who ticks first some members might have already moved
				//and some might have not.
				ori.MoveGroup(1);
			}
		}

		//Print no (additional) warnings if we're not supposed to have a interpolation point
		if (!args[ARG_NODETID])
		{
			//In case the mapper placed walking monsters on the platform
			//get something for HandleOldPassengers() to monitor.
			GetNewPassengers(true);
			return; 
		}

		let it = level.CreateActorIterator(args[ARG_NODETID], "InterpolationPoint");
		firstNode = InterpolationPoint(it.Next());
		if (!firstNode)
		{
			Console.Printf(prefix .. "Can't find interpolation point with tid " .. args[ARG_NODETID] .. ".");
			return;
		}

		//Verify the path has enough nodes
		if (firstNode is "FCW_PlatformNode")
			FCW_PlatformNode(firstNode).PNodeFormChain();
		else
			firstNode.FormChain();

		goToNode = (args[ARG_OPTIONS] & OPTFLAG_GOTONODE);

		if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
		{
			//Linear path; need 2 nodes unless the first node is the destination
			if (!goToNode && !firstNode.next)
			{
				Console.Printf(prefix .. "Path needs at least 2 nodes.");
				return;
			}
		}
		else //Spline path; need 4 nodes unless the first node is the destination
		{
			if (!goToNode && (
				!firstNode.next ||
				!firstNode.next.next ||
				!firstNode.next.next.next) )
			{
				Console.Printf(prefix .. "Path needs at least 4 nodes.");
				return;
			}

			//If the first node is in a loop, we can start there.
			//Otherwise, we need to start at the second node in the path.
			let node = firstNode;
			Array<InterpolationPoint> checkedNodes;
			while (node.next && node.next != firstNode && checkedNodes.Find(node) >= checkedNodes.Size())
			{
				checkedNodes.Push(node);
				node = node.next;
			}

			if (node.next == firstNode)
			{
				firstPrevNode = node;
			}
			else if (!goToNode)
			{
				firstPrevNode = firstNode;
				firstNode = firstNode.next;
			}
		}

		if (args[ARG_OPTIONS] & OPTFLAG_STARTACTIVE)
			Activate(self);
		else							//In case the mapper placed walking monsters on the platform
			GetNewPassengers(true);		//get something for HandleOldPassengers() to monitor.
	}

	//============================
	// OnDestroy (override)
	//============================
	override void OnDestroy ()
	{
		if (portTwin)
		{
			if (portTwin.portTwin == self)
				portTwin.portTwin = null; //No infinite recursions
			portTwin.Destroy();
		}
		Super.OnDestroy();
	}

	//============================
	// CanCollideWith (override)
	//============================
	override bool CanCollideWith (Actor other, bool passive)
	{
		let plat = FCW_Platform(other);
		if (plat)
		{
			if (plat == portTwin)
				return false; //Don't collide with portal twin

			if (group && group == plat.group)
				return false; //Don't collide with groupmates

			if (portTwin && portTwin.group && portTwin.group == plat.group)
				return false; //Don't collide with portal twin's groupmates

			if (args[ARG_OPTIONS] & OPTFLAG_IGNOREGEO)
				return false; //Don't collide with any platform in general
		}

		if (passive && stuckActors.Find(other) < stuckActors.Size())
			return false; //Let stuck things move out/move through us - also makes pushing them away easier

		if (bPlatInMove || (portTwin && portTwin.bPlatInMove))
		{
			//If me or my twin is moving, don't
			//collide with either one's passengers.
			if (passengers.Find(other) < passengers.Size())
				return false;

			if (portTwin && portTwin.passengers.Find(other) < portTwin.passengers.Size())
				return false;
		}
		return true;
	}

	//============================
	// CollisionFlagChecks
	//============================
	static bool CollisionFlagChecks (Actor a, Actor b)
	{
		if (a.bThruActors || b.bThruActors)
			return false;

		if (!a.bSolid || !b.bSolid)
			return false;

		if ((a.bAllowThruBits || b.bAllowThruBits) && (a.thruBits & b.thruBits))
			return false;

		if ((a.bThruSpecies || b.bThruSpecies) && a.GetSpecies() == b.GetSpecies())
			return false;

		return true;
	}

	//============================
	// OverlapXY
	//============================
	static bool OverlapXY (Actor a, Actor b, double blockDist = 0)
	{
		if (!blockDist)
			blockDist = a.radius + b.radius;

		vector2 vec = level.Vec2Diff(a.pos.xy, b.pos.xy);
		return (abs(vec.x) < blockDist && abs(vec.y) < blockDist);
	}

	//============================
	// OverlapZ
	//============================
	static bool OverlapZ (Actor a, Actor b)
	{
		return (a.pos.z + a.height > b.pos.z &&
				b.pos.z + b.height > a.pos.z);
	}

	//============================
	// FitsAtPosition
	//============================
	static bool FitsAtPosition (Actor mo, vector3 testPos)
	{
		//Unlike TestMobjLocation(), CheckMove() takes into account
		//actors that have the flags FLOORHUGGER, CEILINGHUGGER
		//and CANTLEAVEFLOORPIC.

		let oldZ = mo.pos.z;
		mo.SetZ(testPos.z); //Because setting Z has an effect on CheckMove()'s outcome

		FCheckPosition tm;
		bool result = (mo.CheckMove(testPos.xy, 0, tm) &&
			testPos.z >= tm.floorZ &&				//This is something that TestMobjLocation() checks
			testPos.z + mo.height <= tm.ceilingZ);	//and that CheckMove() does not account for.

		mo.SetZ(oldZ);
		return result;
	}

	//============================
	// IsBehindLine
	//============================
	static clearscope bool IsBehindLine (vector2 v, Line l)
	{
		//Yes, this is borrowed from P_PointOnLineSidePrecise()
		return ( (v.y - l.v1.p.y) * l.delta.x + (l.v1.p.x - v.x) * l.delta.y > ZS_EQUAL_EPSILON );
	}

	//============================
	// IsOnLine
	//============================
	static clearscope bool IsOnLine (vector2 v, Line l)
	{
		//Ditto
		return ( abs( (v.y - l.v1.p.y) * l.delta.x + (l.v1.p.x - v.x) * l.delta.y ) < ZS_EQUAL_EPSILON );
	}

	//============================
	// PushObstacle
	//============================
	private void PushObstacle (Actor pushed, vector3 pushForce)
	{
		//Respect CANNOTPUSH and DONTTHRUST unless it's a stuck actor
		if ((bCannotPush || pushed.bDontThrust) &&
			stuckActors.Find(pushed) >= stuckActors.Size())
		{
			pushForce = (0, 0, 0);
		}
		else
		{
			//Don't bother if it's close to nothing
			if (pushForce.x ~== 0) pushForce.x = 0;
			if (pushForce.y ~== 0) pushForce.y = 0;
			if (pushForce.z ~== 0) pushForce.z = 0;
		}

		if (pushForce.z && !OverlapXY(self, pushed)) //Out of XY range?
			pushForce.z = 0;

		let oldZ = pushForce.z;
		if (pushed.bCantLeaveFloorPic || //No Z pushing for CANTLEAVEFLOORPIC actors.
			pushed.bFloorHugger || pushed.bCeilingHugger) //No Z pushing for floor/ceiling huggers.
		{
			pushForce.z = 0;
		}
		pushed.vel += pushForce;
		pushForce.z = oldZ; //Still use it for FitsAtPosition()

		int crushDamage = args[ARG_CRUSHDMG];
		if (crushDamage <= 0)
			return;

		//Normally, if the obstacle is pushed against a wall or solid actor etc
		//then apply damage every 4th tic so its pain sound can be heard.
		//But if it's not pushed against anything and 'hurtfulPush' is enabled
		//then always apply damage.
		//However, if there was no 'pushForce' whatsoever and 'hurtfulPush' is
		//desired then the "damage every 4th tic" rule always applies.
		bool hurtfulPush = (args[ARG_OPTIONS] & OPTFLAG_HURTFULPUSH);
		if (pushForce == (0, 0, 0))
		{
			if (hurtfulPush && !(level.mapTime & 3))
			{
				int doneDamage = pushed.DamageMobj(null, null, crushDamage, 'Crush');
				pushed.TraceBleed(doneDamage > 0 ? doneDamage : crushDamage, self);
			}
			return;
		}

		//If it 'fits' then it's not being pushed against anything
		bool fits = FitsAtPosition(pushed, level.Vec3Offset(pushed.pos, pushForce));
		if ((!fits && !(level.mapTime & 3)) || (fits && hurtfulPush))
		{
			int doneDamage = pushed.DamageMobj(null, null, crushDamage, 'Crush');
			pushed.TraceBleed(doneDamage > 0 ? doneDamage : crushDamage, self);
		}
	}

	//============================
	// SetTimeFraction
	//============================
	private void SetTimeFraction ()
	{
		if (!currNode)
			return;

		int newTime = currNode.args[NODEARG_TRAVELTIME];
		if (newTime <= 0)
		{
			timeFrac = 1.0; //Ignore time unit if it's supposed to be "instant"
			return;
		}

		if (currNode is "FCW_PlatformNode")
		{
			switch (currNode.args[NODEARG_TRAVELTUNIT])
			{
				default:
				case TIMEUNIT_OCTICS:
					timeFrac = 8.0 / (newTime * TICRATE);
					break;
				case TIMEUNIT_TICS:
					timeFrac = 1.0 / newTime;
					break;
				case TIMEUNIT_SECS:
					timeFrac = 1.0 / (newTime * TICRATE);
					break;
			}
		}
		else // Old InterpolationPoint class, always in octics
		{
			timeFrac = 8.0 / (newTime * TICRATE);
		}
	}

	//============================
	// SetHoldTime
	//============================
	private void SetHoldTime ()
	{
		if (!currNode)
			return;

		int newTime = currNode.args[NODEARG_HOLDTIME];
		if (newTime <= 0)
			return;

		if (currNode is "FCW_PlatformNode")
		{
			switch (currNode.args[NODEARG_HOLDTUNIT])
			{
				default:
				case TIMEUNIT_OCTICS:
					holdTime = newTime * TICRATE / 8;
					break;
				case TIMEUNIT_TICS:
					holdTime = newTime;
					break;
				case TIMEUNIT_SECS:
					holdTime = newTime * TICRATE;
					break;
			}
		}
		else //Old InterpolationPoint class, always in octics
		{
			holdTime = newTime * TICRATE / 8;
		}
	}

	//============================
	// SetInterpolationCoordinates
	//============================
	private void SetInterpolationCoordinates ()
	{
		bool changeAng = (args[ARG_OPTIONS] & OPTFLAG_ANGLE);
		bool changePi = (args[ARG_OPTIONS] & OPTFLAG_PITCH);
		bool changeRo = (args[ARG_OPTIONS] & OPTFLAG_ROLL);

		//Take into account angle changes when
		//passing through non-static line portals.
		//All checked angles have to be adjusted.
		double delta = (currNode && changeAng && !goToNode) ? DeltaAngle(currNode.angle, angle) : 0;
		if (prevNode && !goToNode)
		{
			//'pPrev' has to be adjusted if 'currNode' position is different from platform's.
			//Which can happen because of non-static line portals.
			//(But to be perfectly honest, the offsetting done here is
			//arbitrary on my part because the differences on
			//a spline path, with or without the offsetting, are subtle.)
			vector3 offset = currNode ? currNode.Vec3To(self) : (0, 0, 0);
			pPrev = pos + Vec3To(prevNode) + offset; //Make it portal aware in a way so TryMove() can handle it
			pPrevAngs = (
			changeAng ? Normalize180(prevNode.angle + delta) : angle,
			changePi  ? Normalize180(prevNode.pitch) : pitch,
			changeRo  ? Normalize180(prevNode.roll) : roll);
		}

		pCurr = pos;
		if (!prevNode || goToNode)
		{
			pCurrAngs = (
			changeAng ? Normalize180(angle) : angle,
			changePi  ? Normalize180(pitch) : pitch,
			changeRo  ? Normalize180(roll) : roll);
		}
		else
		{
			pCurrAngs = pPrevAngs + (
			changeAng ? DeltaAngle(pPrevAngs.x, angle) : 0,
			changePi  ? DeltaAngle(pPrevAngs.y, pitch) : 0,
			changeRo  ? DeltaAngle(pPrevAngs.z, roll) : 0);
		}

		if (currNode && (currNode.next || goToNode))
		{
			InterpolationPoint nextNode = goToNode ? currNode : currNode.next;

			pNext = pos + Vec3To(nextNode); //Make it portal aware in a way so TryMove() can handle it
			pNextAngs = pCurrAngs + (
			changeAng ? DeltaAngle(pCurrAngs.x, nextNode.angle + delta) : 0,
			changePi  ? DeltaAngle(pCurrAngs.y, nextNode.pitch) : 0,
			changeRo  ? DeltaAngle(pCurrAngs.z, nextNode.roll)  : 0);

			if (nextNode.next)
			{
				pNextNext = pos + Vec3To(nextNode.next); //Make it portal aware in a way so TryMove() can handle it
				pNextNextAngs = pNextAngs + (
				changeAng ? DeltaAngle(pNextAngs.x, nextNode.next.angle + delta) : 0,
				changePi  ? DeltaAngle(pNextAngs.y, nextNode.next.pitch) : 0,
				changeRo  ? DeltaAngle(pNextAngs.z, nextNode.next.roll)  : 0);
			}
			else //No nextNode.next
			{
				pNextNext = pNext;
				pNextNextAngs = pNextAngs;
			}
		}

		if (!currNode || (!currNode.next && !goToNode))
		{
			pNextNext = pNext = pCurr;
			pNextNextAngs = pNextAngs = pCurrAngs;
		}

		if (!prevNode || goToNode)
		{
			pPrev = pCurr;
			pPrevAngs = pCurrAngs;
		}
	}

	//============================
	// IsCarriable
	//============================
	static bool IsCarriable (Actor mo)
	{
		//Due to how the engine handles actor-to-actor interactions
		//we can only carry things with the CANPASS or the
		//SPECIAL flag. Anything else will just fall through.
		//Even when we have ACTLIKEBRIDGE.
		if (!mo.bCanPass && !mo.bSpecial)
			return false;

		//Don't bother with floor/ceiling huggers since
		//they're not meant to be in mid-air.
		if (mo.bFloorHugger || mo.bCeilingHugger)
			return false;

		//Apparently CANTLEAVEFLOORPIC is similiar to FLOORHUGGER?
		//Because any move that results in its Z being different
		//from its 'floorZ' is invalid according to CheckMove().
		if (mo.bCantLeaveFloorPic)
			return false;

		return true;
	}

	//============================
	// GetNewPassengers
	//============================
	private bool GetNewPassengers (bool ignoreObs)
	{
		//In addition to fetching passengers, this is where corpses get crushed, too. Items won't get destroyed.
		//Returns false if one or more actors are completely stuck inside platform unless 'ignoreObs' is true.

		double top = pos.z + height;
		Array<Actor> miscActors; //The actors on top of the passengers (We'll move those, too)
		Array<Actor> onTopOfMe;
		Array<FCW_Platform> otherPlats;

		//Call Grind() after we're done iterating because destroying
		//actors during iteration can mess up the iterator.
		Array<Actor> corpses;

		//Three things to do here when iterating:
		//1) Gather eligible passengers.
		//2) Gather stuck actors.
		//3) Gather corpses for "grinding."
		bool result = true;

		let it = BlockThingsIterator.Create(self);
		while (it.Next())
		{
			let mo = it.thing;
			if (mo == self || mo == portTwin)
				continue;

			if (portTwin && portTwin.passengers.Find(mo) < portTwin.passengers.Size())
				continue; //Never take your twin's passengers (not here anyway)

			bool canCarry = (IsCarriable(mo) && !(mo is "FCW_Platform")); //Platforms shouldn't carry other platforms.
			bool oldPassenger = (passengers.Find(mo) < passengers.Size());
			if (mo is "FCW_Platform")
				otherPlats.Push(FCW_Platform(mo));

			//Check XY overlap
			double blockDist = radius + mo.radius;
			if (abs(it.position.x - mo.pos.x) < blockDist && abs(it.position.y - mo.pos.y) < blockDist)
			{
				//'ignoreObs' makes anything above our 'top' legit unless there's a 3D floor in the way.
				if (mo.pos.z >= top - TOP_EPSILON && (ignoreObs || mo.pos.z <= top + TOP_EPSILON) && //On top of us?
					mo.floorZ <= top + TOP_EPSILON) //No 3D floor above our 'top' that's below 'mo'?
				{
					if (canCarry && !oldPassenger)
						onTopOfMe.Push(mo);
					continue;
				}

				if (OverlapZ(self, mo))
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
						if (canCarry && top - mo.pos.z <= mo.maxStepHeight)
						{
							blocked = !FitsAtPosition(mo, (mo.pos.xy, top));
							if (!blocked)
							{
								mo.SetZ(top);
								mo.CheckPortalTransition(); //Handle sector portals properly
							}
						}
						if (blocked)
						{
							if (!ignoreObs)
							{
								result = false;
								if (stuckActors.Find(mo) >= stuckActors.Size())
									stuckActors.Push(mo);
							}
							continue;
						}
						if (!oldPassenger)
							onTopOfMe.Push(mo);
					}
					else if (mo is "Inventory" && mo.bSpecial) //Item that can be picked up?
					{
						//Try to correct 'mo' Z so it can ride us, too.
						//But only if its 'maxStepHeight' allows it.
						if (canCarry && top - mo.pos.z <= mo.maxStepHeight &&
							FitsAtPosition(mo, (mo.pos.xy, top)))
						{
							mo.SetZ(top);
							mo.CheckPortalTransition(); //Handle sector portals properly
							if (!oldPassenger)
								onTopOfMe.Push(mo);
						}
					}
					continue;
				}
			}

			if (canCarry && !oldPassenger)
				miscActors.Push(mo); //We'll compare this later against the passengers
		}

		for (int i = 0; i < corpses.Size(); ++i)
			corpses[i].Grind(false);

		if (!onTopOfMe.Size() && !miscActors.Size())
			return result; //Found nothing new so stop here

		//Take into account the possibility that not all
		//group members can be found in a blockmap search.
		if (group)
		for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
		{
			let plat = group.GetMember(iPlat);
			if (plat && plat != self && otherPlats.Find(plat) >= otherPlats.Size())
				otherPlats.Push(plat);
		}

		for (int iPlat = 0; iPlat < otherPlats.Size(); ++iPlat)
		{
			let plat = otherPlats[iPlat];

			for (int i = 0; i < onTopOfMe.Size(); ++i)
			{
				let index = plat.passengers.Find(onTopOfMe[i]);
				if (index < plat.passengers.Size())
				{
					//Steal other platforms' passengers if
					//A) We don't share groups and our 'top' is higher or...
					//B) We don't share the "mirror" setting and the passenger's center is within our radius
					//and NOT within the other platform's radius.
					//(In other words, groupmates with the same "mirror" setting never steal each other's passengers.)
					bool stealPassenger;
					if (!group || group != plat.group)
						stealPassenger = (top > plat.pos.z + plat.height);
					else
						stealPassenger = (
							(args[ARG_OPTIONS] & OPTFLAG_MIRROR) != (plat.args[ARG_OPTIONS] & OPTFLAG_MIRROR) &&
							OverlapXY(self, onTopOfMe[i], radius) && !OverlapXY(plat, onTopOfMe[i], plat.radius) );

					if (stealPassenger)
						plat.passengers.Delete(index);
					else
						onTopOfMe.Delete(i--);
				}
			}
			for (int i = 0; i < miscActors.Size(); ++i)
			{
				if (plat.passengers.Find(miscActors[i]) < plat.passengers.Size())
					miscActors.Delete(i--);
			}
		}
		passengers.Append(onTopOfMe);

		//Now figure out which of the misc actors are on top of/stuck inside
		//established passengers.
		for (int i = 0; miscActors.Size() && i < passengers.Size(); ++i)
		{
			let mo = passengers[i];
			if (!mo)
			{
				passengers.Delete(i--);
				continue;
			}
			double moTop = mo.pos.z + mo.height;

			for (int iOther = 0; iOther < miscActors.Size(); ++iOther)
			{
				let otherMo = miscActors[iOther];

				if ( ( abs(otherMo.pos.z - moTop) <= TOP_EPSILON || OverlapZ(mo, otherMo) ) && //Is 'otherMo' on top of 'mo' or stuck inside 'mo'?
					OverlapXY(mo, otherMo) ) //Within XY range?
				{
					miscActors.Delete(iOther--); //Don't compare this one against other passengers anymore
					passengers.Push(otherMo);
				}
			}
		}
		return result;
	}

	//============================
	// MovePassengers
	//============================
	private bool MovePassengers (vector3 startPos, vector3 endPos, double forward, double delta, double piDelta, double roDelta, bool teleMove)
	{
		//Returns false if a blocked passenger would block the platform's movement unless 'teleMove' is true

		if (!passengers.Size())
			return true; //No passengers? Nothing to do

		//The goal is to move all passengers as if they were one entity.
		//The only things that should block any of them are
		//non-passengers and geometry.
		//The exception is if a passenger can't fit at its new position
		//in which case it will be "solid" for the others.
		//
		//To accomplish this each of them will temporarily
		//be removed from the blockmap.

		for (int i = 0; i < passengers.Size(); ++i)
		{
			let mo = passengers[i];
			if (mo && !mo.bNoBlockmap)
			{
				mo.A_ChangeLinkFlags(NO_BMAP);
			}
			else
			{
				passengers.Delete(i--);
				if (!passengers.Size())
					return true; //No passengers? Nothing to do
			}
		}

		//We have to do the same for our portal twin's passengers
		if (portTwin)
		for (int i = 0; i < portTwin.passengers.Size(); ++i)
		{
			let mo = portTwin.passengers[i];
			if (mo && !mo.bNoBlockmap)
				mo.A_ChangeLinkFlags(NO_BMAP);
			else
				portTwin.passengers.Delete(i--);
		}

		//Move our passengers (platform rotation is taken into account)
		double top = endPos.z + height;
		double c = cos(delta), s = sin(delta);
		vector2 piAndRoOffset = (0, 0);
		if (piDelta || roDelta)
		{
			piDelta *= 2;
			roDelta *= 2;
			piAndRoOffset = (cos(forward)*piDelta, sin(forward)*piDelta) + //Front/back
				(cos(forward-90)*roDelta, sin(forward-90)*roDelta); //Right/left
		}

		Array<double> preMovePos; //Sadly we can't have a vector2/3 dyn array
		for (int i = 0; i < passengers.Size(); ++i)
		{
			let mo = passengers[i];
			let moOldPos = mo.pos;

			vector3 offset = level.Vec3Diff(startPos, moOldPos);
			offset.xy = (offset.x*c - offset.y*s, offset.x*s + offset.y*c); //Rotate it
			offset.xy += piAndRoOffset;
			vector3 moNewPos = level.Vec3Offset(endPos, offset, !teleMove);

			//Handle z discrepancy
			if (moNewPos.z < top && moNewPos.z + mo.height >= top)
				moNewPos.z = top;

			bool moved;
			if (teleMove)
			{
				moved = FitsAtPosition(mo, moNewPos);
				if (moved)
				{
					mo.SetOrigin(moNewPos, false);
					mo.CheckPortalTransition(); //Handle sector portals properly
				}
			}
			else
			{
				int maxSteps = 1;
				vector3 stepMove = level.Vec3Diff(moOldPos, moNewPos);

				//If the move is equal or larger than the passenger's radius
				//then it has to be split up into smaller steps.
				//This is needed for proper collision and to ensure
				//lines with specials aren't skipped.
				double maxMove = max(1, mo.radius - 1);
				double moveSpeed = max(abs(stepMove.x), abs(stepMove.y));
				if (moveSpeed > maxMove)
				{
					maxSteps = int(1 + moveSpeed / maxMove);
					stepMove /= maxSteps;
				}

				//NODROPOFF overrides TryMove()'s second argument,
				//but the passenger should be treated like a flying object.
				let moOldNoDropoff = mo.bNoDropoff;
				mo.bNoDropoff = false;
				moved = true;
				for (int step = 0; step < maxSteps; ++step)
				{
					let moOldAngle = mo.angle;
					let moOldZ = mo.pos.z;
					mo.AddZ(stepMove.z);
					vector2 tryPos = mo.pos.xy + stepMove.xy;
					if (!mo.TryMove(tryPos, 1))
					{
						mo.SetZ(moOldZ);
						moved = false;
						break;
					}

					//Take into account passengers getting Thing_Remove()'d
					//when they activate lines.
					if (!mo || mo.bDestroyed)
						break;

					if (tryPos != mo.pos.xy)
					{
						//If 'mo' has passed through a portal then
						//adjust 'stepMove' if its angle changed.
						double angDiff = DeltaAngle(moOldAngle, mo.angle);
						if (angDiff)
						{
							if (step < maxSteps-1)
								stepMove.xy = RotateVector(stepMove.xy, angDiff);

							//Adjust 'moveDir' for monsters
							if (mo.bIsMonster)
								mo.moveDir = (mo.moveDir + int(angDiff / 45)) & 7;
						}
					}
					mo.CheckPortalTransition(); //Handle sector portals properly
				}

				//Take into account passengers getting Thing_Remove()'d
				//when they activate lines.
				if (!mo || mo.bDestroyed)
				{
					passengers.Delete(i--);
					continue;
				}
				mo.bNoDropoff = moOldNoDropoff;
			}

			if (moved)
			{
				//Only remember the old position if 'mo' was moved.
				//(Else we delete the 'passengers' entry containing 'mo', see below.)
				preMovePos.Push(moOldPos.x);
				preMovePos.Push(moOldPos.y);
				preMovePos.Push(moOldPos.z);
			}
			else
			{
				if (mo.pos != moOldPos)
					mo.SetOrigin(moOldPos, true);

				//This passenger will be 'solid' for the others
				mo.A_ChangeLinkFlags(YES_BMAP);
				passengers.Delete(i--);

				//See if 'mo' would block the platform
				let realPos = pos;
				SetXYZ(endPos);
				bool blocked = ( !teleMove && CollisionFlagChecks(mo, self) &&
					OverlapZ(mo, self) && //Within Z range?
					OverlapXY(mo, self) && //Within XY range?
					mo.CanCollideWith(self, false) && self.CanCollideWith(mo, true) );
				SetXYZ(realPos);

				//See if the ones we moved already will collide with this one
				//and if yes, move them back to their old positions.
				//(If the platform's "blocked" then move everyone back unconditionally.)
				for (int iOther = 0; iOther <= i; ++iOther)
				{
					let otherMo = passengers[iOther];
					if ( !blocked && ( !CollisionFlagChecks(otherMo, mo) ||
						!OverlapZ(otherMo, mo) || //Out of Z range?
						!OverlapXY(otherMo, mo) || //Out of XY range?
						!otherMo.CanCollideWith(mo, false) || !mo.CanCollideWith(otherMo, true) ) )
					{
						continue;
					}

					//Put 'otherMo' back at its old position
					vector3 otherOldPos = (preMovePos[iOther*3], preMovePos[iOther*3 + 1], preMovePos[iOther*3 + 2]);
					otherMo.SetOrigin(otherOldPos, true);

					otherMo.A_ChangeLinkFlags(YES_BMAP);
					preMovePos.Delete(iOther*3, 3);
					passengers.Delete(iOther--);
					i--;
				}

				if (blocked)
				{
					for (i = 0; i < passengers.Size(); ++i)
						passengers[i].A_ChangeLinkFlags(YES_BMAP); //Handle those that didn't get the chance to move

					if (portTwin)
					for (i = 0; i < portTwin.passengers.Size(); ++i)
						portTwin.passengers[i].A_ChangeLinkFlags(YES_BMAP);

					PushObstacle(mo, level.Vec3Diff(startPos, endPos));
					return false;
				}
			}
		}

		//Anyone left in the 'passengers' array has moved successfully.
		//Change their angles.
		for (int i = 0; i < passengers.Size(); ++i)
		{
			let mo = passengers[i];
			mo.A_ChangeLinkFlags(YES_BMAP);
			if (delta)
				mo.A_SetAngle(Normalize180(mo.angle + delta), SPF_INTERPOLATE);
		}

		if (portTwin)
		for (int i = 0; i < portTwin.passengers.Size(); ++i)
			portTwin.passengers[i].A_ChangeLinkFlags(YES_BMAP);

		return true;
	}

	//============================
	// HandleOldPassengers
	//============================
	private void HandleOldPassengers ()
	{
		// Tracks established passengers and doesn't forget them even if
		// they're above our 'top' (with no 3D floors in between).
		// Such actors are mostly jumpy players and custom AI.
		//
		// Also keep non-flying monsters away from platform's edge.
		// Because the AI's native handling of trying not to
		// fall off of other actors just isn't good enough.

		double top = pos.z + height;
		for (int i = 0; i < passengers.Size(); ++i)
		{
			let mo = passengers[i];
			if (!mo || mo.bDestroyed || //Got Thing_Remove()'d?
				mo.bNoBlockmap || !IsCarriable(mo))
			{
				passengers.Delete(i--);
				continue;
			}

			//'floorZ' can be the top of a 3D floor that's right below an actor.
			//No 3D floors means 'floorZ' is the current sector's floor height.
			//(In other words 'floorZ' is not another actor's top that's below.)

			//Is 'mo' below our 'top'? Or is there a 3D floor above our 'top' that's also below 'mo'?
			if (mo.pos.z < top - TOP_EPSILON || mo.floorZ > top + TOP_EPSILON ||
				!OverlapXY(self, mo)) //Is out of XY range?
			{
				//Add velocity to the passenger we just lost track of.
				//It's likely to be a player that has jumped away.
				if (args[ARG_OPTIONS] & OPTFLAG_ADDVELJUMP)
					mo.vel += level.Vec3Diff(oldPos, pos);

				passengers.Delete(i--);
				continue;
			}

			//See if we should keep it away from the edge
			if (!mo.bIsMonster || mo.bNoGravity || mo.bFloat || !mo.speed) //Is not a walking monster?
				continue;

			if (mo.bDropoff || mo.bJumpDown) //Is supposed to fall off of tall drops or jump down?
				continue;

			if (mo.tics != 1 && mo.tics != 0)
				continue; //Don't bother if it's not about to change states (and potentially call A_Chase()/A_Wander())

			if (mo.pos.z > top + TOP_EPSILON)
				continue; //Not exactly on top of us

			if (mo.pos.z - mo.floorZ <= mo.maxDropoffHeight)
				continue; //Monster is close to the ground (which includes 3D floors) so let it walk off

			if (Distance2D(mo) < radius - mo.speed)
				continue; //Not close to platform's edge

			// Make your bog-standard idTech1 AI
			// that uses A_Chase() or A_Wander()
			// walk towards the platform's center.
			//
			// NOTE: This isn't fool proof if there
			// are multiple passengers moving on the
			// same platform at the same time.
			//
			// Yes, this is a hack.

			mo.moveDir = int(mo.AngleTo(self) / 45) & 7;
			if (mo.moveCount < 1)
				mo.moveCount = 1;
		}

		oldPos = pos;
		oldAngle = angle;
		oldPitch = pitch;
		oldRoll = roll;
	}

	//============================
	// GetUnlinkedPortal
	//============================
	private Line GetUnlinkedPortal ()
	{
		//Our bounding box
		double size = radius + EXTRA_SIZE; //Pretend we're a bit bigger
		double minX1 = pos.x - size;
		double maxX1 = pos.x + size;
		double minY1 = pos.y - size;
		double maxY1 = pos.y + size;

		BlockLinesIterator it = lastUPort ? null : BlockLinesIterator.Create(self);
		while (lastUPort || it.Next())
		{
			Line port = lastUPort ? lastUPort : it.curLine;
			Line dest;
			if (!port.IsLinePortal() || !(dest = port.GetPortalDestination()))
			{
				if (lastUPort)
				{
					lastUPort = null;
					it = BlockLinesIterator.Create(self);
				}
				continue;
			}

			//To be a linked/static line portal, the portal groups must be non-zero
			//and they must be different.
			if (port.frontSector.portalGroup && dest.frontSector.portalGroup &&
				port.frontSector.portalGroup != dest.frontSector.portalGroup)
			{
				//The angle difference between the two lines must be exactly 180
				if (!DeltaAngle(180 +
					VectorAngle(port.delta.x, port.delta.y),
					VectorAngle(dest.delta.x, dest.delta.y)))
				{
					if (lastUPort)
					{
						lastUPort = null;
						it = BlockLinesIterator.Create(self);
					}
					continue; //We don't want linked/static line portals
				}
			}

			//Line bounding box
			double minX2 = min(port.v1.p.x, port.v2.p.x);
			double maxX2 = max(port.v1.p.x, port.v2.p.x);
			double minY2 = min(port.v1.p.y, port.v2.p.y);
			double maxY2 = max(port.v1.p.y, port.v2.p.y);

			if (minX1 >= maxX2 || minX2 >= maxX1 ||
				minY1 >= maxY2 || minY2 >= maxY1)
			{
				if (lastUPort)
				{
					lastUPort = null;
					it = BlockLinesIterator.Create(self);
				}
				continue; //BBoxes not intersecting
			}

			if (IsBehindLine(pos.xy, port))
			{
				if (lastUPort)
				{
					lastUPort = null;
					it = BlockLinesIterator.Create(self);
				}
				continue; //Center point not in front of line
			}

			bool cornerResult = IsBehindLine((minX1, minY1), port);
			if (cornerResult == IsBehindLine((minX1, maxY1), port) &&
				cornerResult == IsBehindLine((maxX1, minY1), port) &&
				cornerResult == IsBehindLine((maxX1, maxY1), port))
			{
				if (lastUPort)
				{
					lastUPort = null;
					it = BlockLinesIterator.Create(self);
				}
				continue; //All corners on one side; there's no intersection with line
			}
			lastUPort = port;
			return port;
		}
		return null;
	}

	//============================
	// TranslatePortalVector
	//============================
	static vector3, double TranslatePortalVector (vector3 vec, Line port, bool isPos)
	{
		Line dest;
		if (!port || !(dest = port.GetPortalDestination()))
			return vec, 0;

		double delta = DeltaAngle(180 +
		VectorAngle(port.delta.x, port.delta.y),
		VectorAngle(dest.delta.x, dest.delta.y));

		if (isPos)
			vec.xy -= port.v1.p;
		if (delta)
			vec.xy = RotateVector(vec.xy, delta);
		if (isPos)
			vec.xy += dest.v2.p;

		if (isPos)
		switch (port.GetPortalAlignment())
		{
			case 1: //Floor
				vec.z += dest.frontSector.floorPlane.ZatPoint(dest.v2.p) - port.frontSector.floorPlane.ZatPoint(port.v1.p);
				break;
			case 2: //Ceiling
				vec.z += dest.frontSector.ceilingPlane.ZatPoint(dest.v2.p) - port.frontSector.ceilingPlane.ZatPoint(port.v1.p);
				break;
		}
		return vec, delta;
	}

	//============================
	// ExchangePassengersWithTwin
	//============================
	private void ExchangePassengersWithTwin ()
	{
		if (!portTwin || portTwin.portTwin != self)
			return;

		int oldPortTwinSize = portTwin.passengers.Size();

		//This is never called by the 'passive' twin,
		//ie the one that can have NOBLOCKMAP set.
		if (!portTwin.bNoBlockmap)
		for (int i = 0; i < passengers.Size(); ++i)
		{
			//If any of our passengers have passed through a portal,
			//check if they're on the twin's side of that portal.
			//If so, give them to our twin.
			let mo = passengers[i];
			if (!mo || mo.bDestroyed)
			{
				passengers.Delete(i--);
				continue;
			}

			if (mo.Distance3D(portTwin) < mo.Distance3D(self) &&
				portTwin.passengers.Find(mo) >= portTwin.passengers.Size())
			{
				passengers.Delete(i--);
				portTwin.passengers.Push(mo);
			}
		}

		for (int i = 0; i < oldPortTwinSize; ++i)
		{
			//Same deal but in reverse
			let mo = portTwin.passengers[i];
			if (!mo || mo.bDestroyed)
			{
				portTwin.passengers.Delete(i--);
				--oldPortTwinSize;
				continue;
			}

			if (mo.Distance3D(self) < mo.Distance3D(portTwin) &&
				passengers.Find(mo) >= passengers.Size())
			{
				portTwin.passengers.Delete(i--);
				--oldPortTwinSize;
				passengers.Push(mo);
			}
		}
	}

	//============================
	// GoBack
	//============================
	private void GoBack ()
	{
		if (pos != oldPos)
			SetOrigin(oldPos, true);
		angle = oldAngle;
		pitch = oldPitch;
		roll = oldRoll;
	}

	//============================
	// PlatTakeOneStep
	//============================
	private bool PlatTakeOneStep (vector3 newPos)
	{
		//The "invisible" portal twin (copy) isn't meant to go through portals.
		//Don't call TryMove() nor Vec3Offset() for it.
		SetZ(newPos.z);
		bool moved = bPortCopy ? FitsAtPosition(self, newPos) : TryMove(newPos.xy, 1);

		if (!moved && blockingMobj && !(blockingMobj is "FCW_Platform"))
		{
			let mo = blockingMobj;
			let moOldZ = mo.pos.z;
			let moNewZ = newPos.z + self.height;

			//If we could carry it, try to set the obstacle on top of us
			//if its 'maxStepHeight' allows it.
			if (moNewZ > moOldZ && moNewZ - moOldZ <= mo.maxStepHeight &&
				IsCarriable(mo) && FitsAtPosition(mo, (mo.pos.xy, moNewZ)))
			{
				mo.SetZ(moNewZ);

				//Try one more time
				moved = bPortCopy ? FitsAtPosition(self, newPos) : TryMove(newPos.xy, 1);
				if (!moved)
				{
					mo.SetZ(moOldZ);
					blockingMobj = mo; //Needed for obstacle pushing; TryMove() might have nulled it
				}
				else
				{
					mo.CheckPortalTransition(); //Handle sector portals properly
				}
			}

			if (!moved) //Blocked by actor that isn't a platform?
			{
				SetZ(oldPos.z);
				return false;
			}
		}

		if (!moved) //Blocked by geometry or another platform?
		{
			if (args[ARG_OPTIONS] & OPTFLAG_IGNOREGEO)
			{
				if (!bPortCopy)
					SetOrigin(level.Vec3Offset(pos, newPos - pos), true);
			}
			else
			{
				SetZ(oldPos.z);
				return false;
			}
		}

		if (bPortCopy)
			SetOrigin(newPos, true);

		return true;
	}

	//============================
	// GetStuckActors
	//============================
	private void GetStuckActors ()
	{
		//A slimmed down version of GetNewPassengers()
		//that only looks for stuck actors.
		let it = BlockThingsIterator.Create(self);
		while (it.Next())
		{
			let mo = it.thing;
			if (mo == self)
				continue;

			if (!CollisionFlagChecks(self, mo))
				continue;

			if (stuckActors.Find(mo) < stuckActors.Size())
				continue; //Already in the array

			double blockDist = radius + mo.radius;
			if (abs(it.position.x - mo.pos.x) >= blockDist || abs(it.position.y - mo.pos.y) >= blockDist)
				continue; //No XY overlap

			if (!OverlapZ(self, mo))
				continue;

			if (self.CanCollideWith(mo, false) && mo.CanCollideWith(self, true))
				stuckActors.Push(mo); //Got one
		}
	}

	//============================
	// HandleStuckActors
	//============================
	private void HandleStuckActors ()
	{
		for (int i = 0; i < stuckActors.Size(); ++i)
		{
			let mo = stuckActors[i];
			if (!mo || mo.bDestroyed || //Thing_Remove()'d?
				!OverlapZ(self, mo) || !OverlapXY(self, mo)) //No overlap?
			{
				stuckActors.Delete(i--);
				continue;
			}

			if (!(mo is "FCW_Platform"))
			{
				vector3 pushForce = level.Vec3Diff(pos, mo.pos + (0, 0, mo.height/2)).Unit();
				PushObstacle(mo, pushForce);
			}
		}
	}

	//============================
	// PlatMove
	//============================
	private bool PlatMove (vector3 newPos, double newAngle, double newPitch, double newRoll, int moveType)
	{
		// moveType values:
		// 0 = normal move
		// 1 = teleport move
		// -1 = quick move
		//
		// "Quick move" is used to correct the position/angles and it is assumed
		// that 'newPos/Angle/Pitch/Roll' is only marginally different from
		// the current position/angles.

		bool quickMove = (moveType == -1);
		bool teleMove = (moveType == 1);

		if (pos == newPos && angle == newAngle && pitch == newPitch && roll == newRoll)
		{
			if (quickMove)
				return false;

			if (teleMove)
				GetNewPassengers(true);

			return true;
		}

		Line port = null;
		if (!teleMove)
		{
			port = GetUnlinkedPortal();
			if (port && !portTwin)
			{
				portTwin = FCW_Platform(Spawn(GetClass(), TranslatePortalVector(pos, port, true)));
				portTwin.portTwin = self;
				portTwin.SetStateLabel("PortalCopy"); //Invisible
				portTwin.bPortCopy = true;
				portTwin.bCannotPush = bCannotPush;
				portTwin.args[ARG_OPTIONS] = (args[ARG_OPTIONS] & (OPTFLAG_IGNOREGEO | OPTFLAG_ADDVELJUMP | OPTFLAG_HURTFULPUSH));
				portTwin.args[ARG_CRUSHDMG] = args[ARG_CRUSHDMG];
			}
		}

		if (portTwin)
		{
			if (portTwin.bNoBlockmap && port)
				portTwin.A_ChangeLinkFlags(YES_BMAP);
			else if (!portTwin.bNoBlockmap && !port)
				portTwin.A_ChangeLinkFlags(NO_BMAP);
		}

		double delta, piDelta, roDelta;
		if (quickMove || teleMove || pos == newPos)
		{
			oldPos = pos;
			oldAngle = angle;
			oldPitch = pitch;
			oldRoll = roll;

			angle = newAngle;
			pitch = newPitch;
			roll = newRoll;

			//For MovePassengers()
			delta = DeltaAngle(oldAngle, newAngle);
			piDelta = teleMove ? 0 : DeltaAngle(oldPitch, newPitch);
			roDelta = teleMove ? 0 : DeltaAngle(oldRoll, newRoll);
		}

		if (quickMove)
		{
			if (pos != newPos)
			{
				SetOrigin(newPos, true);
				let oldPrev = prev;
				CheckPortalTransition(); //Handle sector portals properly
				prev = oldPrev;
			}

			if (port)
			{
				double portDelta;
				[portTwin.oldPos, portDelta] = TranslatePortalVector(oldPos, port, true);
				portTwin.angle = angle + portDelta;

				if (oldPos != newPos)
					portTwin.SetOrigin(TranslatePortalVector(pos, port, true), true);
				else if (portTwin.oldPos != portTwin.pos)
					portTwin.SetOrigin(portTwin.oldPos, true);
			}

			bPlatInMove = true;
			MovePassengers(oldPos, pos, angle, delta, piDelta, roDelta, false);
			if (port)
				portTwin.MovePassengers(portTwin.oldPos, portTwin.pos, portTwin.angle, delta, piDelta, roDelta, false);
			bPlatInMove = false;
			ExchangePassengersWithTwin();

			GetStuckActors();
			if (portTwin)
				portTwin.GetStuckActors();
			return true;
		}

		if (!GetNewPassengers(teleMove) || (port && !portTwin.GetNewPassengers(false)))
		{
			if (teleMove || pos == newPos)
				GoBack();
			return false;
		}

		if (teleMove || pos == newPos)
		{
			if (pos != newPos)
			{
				SetOrigin(newPos, false);
				CheckPortalTransition(); //Handle sector portals properly
			}

			if (teleMove && portTwin && !portTwin.bNoBlockmap)
				portTwin.A_ChangeLinkFlags(NO_BMAP);

			if (!MovePassengers(oldPos, pos, angle, delta, piDelta, roDelta, teleMove))
			{
				GoBack();
				return false;
			}
			return true;
		}

		int maxSteps = 1;
		vector3 stepMove = level.Vec3Diff(pos, newPos);
		vector3 pushForce = stepMove;

		//If the move is equal or larger than our radius
		//then it has to be split up into smaller steps.
		//This is needed for proper collision.
		double maxMove = max(1, radius - 1);
		double moveSpeed = max(abs(stepMove.x), abs(stepMove.y));
		if (moveSpeed > maxMove)
		{
			maxSteps = int(1 + moveSpeed / maxMove);
			stepMove /= maxSteps;
		}

		bPlatInMove = true; //Temporarily don't clip against passengers
		for (int step = 0; step < maxSteps; ++step)
		{
			oldPos = pos;
			oldAngle = angle;
			oldPitch = pitch;
			oldRoll = roll;

			newPos = pos + stepMove;
			if (!PlatTakeOneStep(newPos))
			{
				bPlatInMove = false;
				if (blockingMobj && !(blockingMobj is "FCW_Platform"))
				{
					let mo = blockingMobj;
					if (portTwin && !portTwin.bNoBlockmap && port &&
						mo.Distance3D(portTwin) < mo.Distance3D(self))
					{
						portTwin.PushObstacle(mo, TranslatePortalVector(pushForce, port, false));
					}
					else
					{
						PushObstacle(mo, pushForce);
					}
				}
				return false;
			}

			//For MovePassengers().
			//Any portal induced angle changes
			//should not affect passenger rotation.
			vector3 myStartPos = oldPos;
			delta = (step > 0) ? 0 : DeltaAngle(oldAngle, newAngle);
			piDelta = (step > 0) ? 0 : DeltaAngle(oldPitch, newPitch);
			roDelta = (step > 0) ? 0 : DeltaAngle(oldRoll, newRoll);

			double angDiff;
			if (newPos.xy != pos.xy)
			{
				//If we have passed through a (non-static) portal
				//then adjust 'stepMove' and 'newAngle' if our angle changed.
				//We also need to adjust 'myStartPos' for MovePassengers().
				myStartPos -= newPos;
				angDiff = DeltaAngle(oldAngle, angle);
				if (angDiff)
				{
					myStartPos.xy = RotateVector(myStartPos.xy, angDiff);

					if (step == 0)
						newAngle += angDiff;

					if (step < maxSteps-1)
						stepMove.xy = RotateVector(stepMove.xy, angDiff);
				}
				myStartPos += pos;
			}

			if (step == 0)
			{
				angle = newAngle;
				pitch = newPitch;
				roll = newRoll;
			}

			bool crossedPortal = false;
			if (port)
			{
				vector3 twinPos;
				if (newPos.xy == pos.xy)
				{
					[portTwin.oldPos, angDiff] = TranslatePortalVector(oldPos, port, true);
					portTwin.angle = angle + angDiff;
					twinPos = TranslatePortalVector(pos, port, true);
				}
				else
				{
					portTwin.oldPos = oldPos;
					portTwin.angle = angle - angDiff;
					twinPos = newPos;
					angDiff = 0;
				}

				bool moved = portTwin.PlatTakeOneStep(twinPos);
				if (moved && newPos.xy != pos.xy)
				{
					crossedPortal = true;
					ExchangePassengersWithTwin();
				}
				else if (!moved)
				{
					bPlatInMove = false;
					GoBack();
					if (portTwin.blockingMobj && !(portTwin.blockingMobj is "FCW_Platform"))
					{
						vector3 twinPushForce = pushForce;
						if (angDiff)
							twinPushForce.xy = RotateVector(twinPushForce.xy, angDiff);
						portTwin.PushObstacle(portTwin.blockingMobj, twinPushForce);
					}
					return false;
				}
			}

			bool movedMine = MovePassengers(myStartPos, pos, angle, delta, piDelta, roDelta, false);
			if (!movedMine || (port &&
				!portTwin.MovePassengers(portTwin.oldPos, portTwin.pos, portTwin.angle, delta, piDelta, roDelta, false) ) )
			{
				if (movedMine)
					MovePassengers(pos, myStartPos, angle, -delta, -piDelta, -roDelta, true); //Move them back

				GoBack();
				if (port)
					portTwin.GoBack();

				bPlatInMove = false;
				return false;
			}

			ExchangePassengersWithTwin();
			CheckPortalTransition(); //Handle sector portals properly
			if (crossedPortal)
			{
				lastUPort = port.GetPortalDestination();
				port = GetUnlinkedPortal();
			}
		}
		bPlatInMove = false;
		return true;
	}

	//============================
	// Lerp
	//============================
	private double Lerp (double p1, double p2)
	{
		return (p1 ~== p2) ? p1 : (p1 + time * (p2 - p1));
	}

	//============================
	// Splerp
	//============================
	private double Splerp (double p1, double p2, double p3, double p4)
	{
		if (p2 ~== p3)
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
	// Interpolate
	//============================
	private bool Interpolate ()
	{
		//A heavily modified version of the
		//original function from PathFollower.

		Vector3 dpos = (0, 0, 0);
		if ((args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) && time > 0)
			dpos = pos;

		vector3 newPos;
		double newAngle = angle;
		double newPitch = pitch;
		double newRoll = roll;

		if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
		{
			newPos.x = Lerp(pCurr.x, pNext.x);
			newPos.y = Lerp(pCurr.y, pNext.y);
			newPos.z = Lerp(pCurr.z, pNext.z);
		}
		else //Spline
		{
			newPos.x = Splerp(pPrev.x, pCurr.x, pNext.x, pNextNext.x);
			newPos.y = Splerp(pPrev.y, pCurr.y, pNext.y, pNextNext.y);
			newPos.z = Splerp(pPrev.z, pCurr.z, pNext.z, pNextNext.z);
		}

		if ((args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) && (args[ARG_OPTIONS] & (OPTFLAG_ANGLE | OPTFLAG_PITCH | OPTFLAG_ROLL)))
		{
			if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
			{
				dpos = pNext - pCurr;
			}
			else if (time > 0) //Spline
			{
				dpos = newPos - dpos;
			}
			else if (args[ARG_OPTIONS] & (OPTFLAG_ANGLE | OPTFLAG_PITCH))
			{	//Spline but with time <= 0
				dpos = newPos;
				time = timeFrac;
				newPos.x = Splerp(pPrev.x, pCurr.x, pNext.x, pNextNext.x);
				newPos.y = Splerp(pPrev.y, pCurr.y, pNext.y, pNextNext.y);
				newPos.z = Splerp(pPrev.z, pCurr.z, pNext.z, pNextNext.z);
				time = 0;
				dpos = newPos - dpos;
				newPos -= dpos;
			}

			//Adjust angle
			if (args[ARG_OPTIONS] & OPTFLAG_ANGLE)
				newAngle = VectorAngle(dpos.x, dpos.y);

			//Adjust pitch
			if (args[ARG_OPTIONS] & OPTFLAG_PITCH)
			{
				double dist = dpos.xy.Length();
				newPitch = dist ? VectorAngle(dist, -dpos.z) : 0;
			}

			//Adjust roll
			if (args[ARG_OPTIONS] & OPTFLAG_ROLL)
				newRoll = 0;
		}
		else
		{
			//Whether angle/pitch/roll interpolates or not is
			//determined in the interpolation coordinates.
			//That way the ACS functions aren't restricted
			//by the lack of OPTFLAG_ANGLE/PITCH/ROLL.
			if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
			{
				//Interpolate angle
				newAngle = Lerp(pCurrAngs.x, pNextAngs.x);

				//Interpolate pitch
				newPitch = Lerp(pCurrAngs.y, pNextAngs.y);

				//Interpolate roll
				newRoll = Lerp(pCurrAngs.z, pNextAngs.z);
			}
			else //Spline
			{
				//Interpolate angle
				newAngle = Splerp(pPrevAngs.x, pCurrAngs.x, pNextAngs.x, pNextNextAngs.x);

				//Interpolate pitch
				newPitch = Splerp(pPrevAngs.y, pCurrAngs.y, pNextAngs.y, pNextNextAngs.y);

				//Interpolate roll
				newRoll = Splerp(pPrevAngs.z, pCurrAngs.z, pNextAngs.z, pNextNextAngs.z);
			}
		}

		if (!PlatMove(newPos, newAngle, newPitch, newRoll, 0))
			return false;

		if (pos != newPos) //Crossed a portal?
		{
			//Offset and possibly rotate the coordinates
			pPrev -= newPos;
			pCurr -= newPos;
			pNext -= newPos;
			pNextNext -= newPos;

			double delta = DeltaAngle(newAngle, angle);
			if (delta)
			{
				pPrevAngs.x += delta;
				pCurrAngs.x += delta;
				pNextAngs.x += delta;
				pNextNextAngs.x += delta;

				//Rotate them
				double c = cos(delta), s = sin(delta);
				pPrev.xy = (pPrev.x*c - pPrev.y*s, pPrev.x*s + pPrev.y*c);
				pCurr.xy = (pCurr.x*c - pCurr.y*s, pCurr.x*s + pCurr.y*c);
				pNext.xy = (pNext.x*c - pNext.y*s, pNext.x*s + pNext.y*c);
				pNextNext.xy = (pNextNext.x*c - pNextNext.y*s, pNextNext.x*s + pNextNext.y*c);
			}
			pPrev += pos;
			pCurr += pos;
			pNext += pos;
			pNextNext += pos;
		}

		//If one of our attached platforms is blocked, pretend
		//we're blocked too. (Our move won't be cancelled.)
		return MoveGroup(0);
	}

	//============================
	// MoveGroup
	//============================
	private bool MoveGroup (int moveType)
	{
		if (!group)
			return true;

		double delta = DeltaAngle(spawnAngle, angle);
		double piDelta = DeltaAngle(spawnPitch, pitch);
		double roDelta = DeltaAngle(spawnRoll, roll);

		double cFirst = 0, sFirst = 0;
		double cY, sY;
		double cP, sP;
		double cR, sR;
		double cLast, sLast;

		for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
		{
			let plat = group.GetMember(iPlat);
			if (!plat || plat == self)
				continue;

			bool changeAng = (plat.args[ARG_OPTIONS] & OPTFLAG_ANGLE);
			bool changePi = (plat.args[ARG_OPTIONS] & OPTFLAG_PITCH);
			bool changeRo = (plat.args[ARG_OPTIONS] & OPTFLAG_ROLL);

			vector3 newPos;
			double newAngle = plat.angle;
			double newPitch = plat.pitch;
			double newRoll = plat.roll;

			if (plat.args[ARG_OPTIONS] & OPTFLAG_MIRROR)
			{
				//The way we mirror movement is by getting the offset going
				//from the origin's current position to its 'spawnPoint'
				//and using that to get a offsetted position from
				//the attached platform's 'spawnPoint'.
				//So we pretty much always go in the opposite direction
				//using our 'spawnPoint' as a reference point.
				vector3 offset = level.Vec3Diff(pos, (spawnPoint.xy, spawnZ));
				newPos = level.Vec3Offset((plat.spawnPoint.xy, plat.spawnZ), offset);

				if (changeAng)
					newAngle = plat.spawnAngle - delta;
				if (changePi)
					newPitch = plat.spawnPitch - piDelta;
				if (changeRo)
					newRoll = plat.spawnRoll - roDelta;
			}
			else //Non-mirror movement. Orbiting happens here.
			{
				if (cFirst == sFirst) //Not called cos() and sin() yet?
				{
					//'spawnAngle' is a uint16 but we need it
					//as a double to get the intended orbit result.
					double sAng = spawnAngle;
					cFirst = cos(-sAng); sFirst = sin(-sAng);
					cY = cos(delta);   sY = sin(delta);
					cP = cos(piDelta); sP = sin(piDelta);
					cR = cos(roDelta); sR = sin(roDelta);
					cLast = cos(sAng);   sLast = sin(sAng);
				}
				vector3 offset = level.Vec3Diff((spawnPoint.xy, spawnZ), (plat.spawnPoint.xy, plat.spawnZ));

				//Rotate the offset. The order here matters.
				offset.xy = (offset.x*cFirst - offset.y*sFirst, offset.x*sFirst + offset.y*cFirst); //Rotate to 0 angle degrees of origin
				offset = (offset.x, offset.y*cR - offset.z*sR, offset.y*sR + offset.z*cR);  //X axis (roll)
				offset = (offset.x*cP + offset.z*sP, offset.y, -offset.x*sP + offset.z*cP); //Y axis (pitch)
				offset = (offset.x*cY - offset.y*sY, offset.x*sY + offset.y*cY, offset.z);  //Z axis (yaw/angle)
				offset.xy = (offset.x*cLast - offset.y*sLast, offset.x*sLast + offset.y*cLast); //Rotate back to origin's 'spawnAngle'

				newPos = level.Vec3Offset(pos, offset);

				if (changeAng)
					newAngle = plat.spawnAngle + delta;

				if (changePi || changeRo)
				{
					double diff = DeltaAngle(spawnAngle, plat.spawnAngle);
					double c = cos(diff), s = sin(diff);
					if (changePi)
						newPitch = plat.spawnPitch + piDelta*c - roDelta*s;
					if (changeRo)
						newRoll = plat.spawnRoll + piDelta*s + roDelta*c;
				}
			}

			if (!plat.PlatMove(newPos, newAngle, newPitch, newRoll, moveType) && moveType != -1)
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
		while ((spec = it.Next()) && spec.special)
		{
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
		if (!bActive)
			return;

		if (!group || !group.origin)
		{
			if (time <= 1.0) //Not reached destination?
				Stopped(oldPos, pos);

			if (portTwin && portTwin.bNoBlockmap)
			{
				portTwin.portTwin = null;
				portTwin.Destroy();
			}
		}
		else if (group.origin == self)
		{
			for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
			{
				let plat = group.GetMember(iPlat);
				if (plat)
				{
					if (time <= 1.0) //Not reached destination?
						plat.Stopped(plat.oldPos, plat.pos);

					if (plat.portTwin && plat.portTwin.bNoBlockmap)
					{
						plat.portTwin.portTwin = null;
						plat.portTwin.Destroy();
					}
				}
			}
		}
		bActive = false;
	}

	//============================
	// Activate (override)
	//============================
	override void Activate (Actor activator)
	{
		if (!bActive || (group && group.origin != self))
		{
			if (portTwin)
				portTwin.bActive = false;

			if ((args[ARG_OPTIONS] & OPTFLAG_RESUMEPATH) && time <= 1.0)
			{
				bActive = true;
				if (group)
					group.origin = self;
				return;
			}

			currNode = firstNode;
			prevNode = firstPrevNode;

			if (currNode)
			{
				goToNode = (args[ARG_OPTIONS] & OPTFLAG_GOTONODE);
				if (!goToNode) //Don't call specials if going to 'currNode'
				{
					CallNodeSpecials();
					if (bDestroyed || !currNode || currNode.bDestroyed)
						return; //Abort if we or the node got Thing_Remove()'d
				}
				bActive = true;
				if (group)
					group.origin = self;

				if (!goToNode)
				{
					double newAngle = (args[ARG_OPTIONS] & OPTFLAG_ANGLE) ? currNode.angle : angle;
					double newPitch = (args[ARG_OPTIONS] & OPTFLAG_PITCH) ? currNode.pitch : pitch;
					double newRoll = (args[ARG_OPTIONS] & OPTFLAG_ROLL) ? currNode.roll : roll;
					PlatMove(currNode.pos, newAngle, newPitch, newRoll, 1);
					MoveGroup(1);
				}
				SetInterpolationCoordinates();
				SetTimeFraction();
				SetHoldTime();
				time = 0;
			}
		}
	}

	//============================
	// Stopped
	//============================
	private void Stopped (vector3 startPos, vector3 endPos)
	{
		if (!(args[ARG_OPTIONS] & OPTFLAG_ADDVELSTOP))
			return;

		vector3 pushForce = level.Vec3Diff(startPos, endPos);

		if (passengers.Size())
		{
			for (int i = 0; i < passengers.Size(); ++i)
			{
				let mo = passengers[i];
				if (!mo || mo.bDestroyed)
					passengers.Delete(i--);
				else
					mo.vel += pushForce;
			}
		}

		if (portTwin && !portTwin.bNoBlockmap && portTwin.passengers.Size())
		{
			if (lastUPort)
				pushForce = TranslatePortalVector(pushForce, lastUPort, false);

			for (int i = 0; i < portTwin.passengers.Size(); ++i)
			{
				let mo = portTwin.passengers[i];
				if (!mo || mo.bDestroyed)
					portTwin.passengers.Delete(i--);
				else
					mo.vel += pushForce;
			}
		}
	}

	//============================
	// Tick (override)
	//============================
	override void Tick ()
	{
		//Portal copies aren't meant to think. Not even advance states.
		if (bPortCopy || IsFrozen())
			return;

		if (group)
		{
			if (group.members.Find(self) >= group.members.Size())
				group.members.Push(self); //Ensure we're in the group array

			if (!group.origin && bActive)
				group.origin = self;
		}

		if (!group || !group.origin)
		{
			HandleOldPassengers();
			HandleStuckActors();
			if (portTwin && portTwin.bPortCopy)
			{
				portTwin.HandleOldPassengers();
				portTwin.HandleStuckActors();
			}
		}
		else if (group.origin == self)
		{
			for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
			{
				let plat = group.GetMember(iPlat);
				if (plat)
				{
					plat.HandleOldPassengers();
					plat.HandleStuckActors();
					if (plat.portTwin && plat.portTwin.bPortCopy)
					{
						plat.portTwin.HandleOldPassengers();
						plat.portTwin.HandleStuckActors();
					}
				}
			}
		}

		while (bActive && (!group || group.origin == self))
		{
			if (holdTime > 0)
			{
				--holdTime;
				break;
			}
			if (!Interpolate())
				break;

			time += timeFrac;
			if (time > 1.0) //Reached destination?
			{
				bool goneToNode = goToNode;
				if (goToNode)
				{
					goToNode = false; //Reached 'currNode'
				}
				else
				{
					prevNode = currNode;
					if (currNode)
						currNode = currNode.next;
				}

				if (currNode)
				{
					CallNodeSpecials();
					if (bDestroyed)
						return; //Abort if we got Thing_Remove()'d

					if (prevNode && prevNode.bDestroyed)
						prevNode = null; //Prev node got Thing_Remove()'d

					if (currNode && currNode.bDestroyed)
						currNode = null; //Current node got Thing_Remove()'d

					else if (currNode &&
						currNode.next && currNode.next.bDestroyed)
					{
						currNode.next = null; //Next node got Thing_Remove()'d
					}
					else if (currNode && currNode.next &&
						currNode.next.next && currNode.next.next.bDestroyed)
					{
						currNode.next.next = null; //Last node got Thing_Remove()'d
					}
				}

				bool finishedPath = false;
				if (!currNode || !currNode.next ||
					(!goneToNode && !(args[ARG_OPTIONS] & OPTFLAG_LINEAR) && (!currNode.next.next || !prevNode) ) )
				{
					finishedPath = true;
				}
				else if (currNode)
				{
					SetTimeFraction();
					SetHoldTime();
				}

				//Stopped() must be called before PlatMove() in this case
				if (finishedPath || holdTime > 0)
				{
					if (!group)
					{
						Stopped(oldPos, pos);
					}
					else for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
					{
						let plat = group.GetMember(iPlat);
						if (plat)
							plat.Stopped(plat.oldPos, plat.pos);
					}
				}

				//Make sure we're exactly at our intended position
				bool faceAng = ((args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) && (args[ARG_OPTIONS] & (OPTFLAG_ANGLE)));
				bool facePi = ((args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) && (args[ARG_OPTIONS] & (OPTFLAG_PITCH)));
				bool faceRo = ((args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) && (args[ARG_OPTIONS] & (OPTFLAG_ROLL)));
				if (PlatMove(pNext, faceAng ? angle : pNextAngs.x,
									facePi ? pitch : pNextAngs.y,
									faceRo ? roll : pNextAngs.z, -1))
				{
					MoveGroup(-1);
				}

				if (finishedPath)
				{
					Deactivate(self);
				}
				else
				{
					SetInterpolationCoordinates();
					time -= 1.0;
				}
			}
			break;
		}

		if (!group || !group.origin)
		{
			AdvanceStates();
		}
		else if (group.origin == self)
		{
			for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
			{
				let plat = group.GetMember(iPlat);
				if (plat)
					plat.AdvanceStates();
			}
		}
	}

	//============================
	// AdvanceStates
	//============================
	private void AdvanceStates ()
	{
		if (!CheckNoDelay())
			return; //Freed itself (ie got destroyed)

		if (tics != -1 && --tics <= 0)
			SetState(curState.nextState);
	}

	//============================
	// CommonACSSetup
	//============================
	private void CommonACSSetup (int travelTime)
	{
		currNode = null; //Deactivate when done moving
		prevNode = null;
		time = 0;
		holdTime = 0;
		timeFrac = 1.0 / max(1, travelTime); //Time unit is always in tics from the ACS side
		bActive = true;
		if (group) group.origin = self;
		pPrev = pCurr = pos;
		pPrevAngs = pCurrAngs = (
			Normalize180(angle),
			Normalize180(pitch),
			Normalize180(roll));
	}

	//
	//
	// Everything below this point is either for
	// scripting convenience with subclasses or
	// ACS centric utility functions.
	//
	//

	//============================
	// Move (ACS utility)
	//============================
	static void Move (int platTid, double x, double y, double z, bool exactPos, int travelTime, double ang = 0, double pi = 0, double ro = 0, bool exactAngs = false)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while (plat = FCW_Platform(it.Next()))
		{
			plat.CommonACSSetup(travelTime);

			plat.pNext = plat.pNextNext = plat.pos + (exactPos ?
				level.Vec3Diff(plat.pos, (x, y, z)) : //Make it portal aware in a way so TryMove() can handle it
				(x, y, z)); //Absolute offset so TryMove() can handle it

			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (
				exactAngs ? DeltaAngle(plat.pCurrAngs.x, ang) : ang,
				exactAngs ? DeltaAngle(plat.pCurrAngs.y, pi) : pi,
				exactAngs ? DeltaAngle(plat.pCurrAngs.z, ro) : ro);
		}
	}

	//============================
	// MoveToSpot (ACS utility)
	//============================
	static void MoveToSpot (int platTid, int spotTid, int travelTime, bool dontRotate = false)
	{
		//This is the only place you can make a platform use any actor as a travel destination
		let it = level.CreateActorIterator(spotTid);
		Actor spot = it.Next();
		if (!spot)
			return; //No spot? Nothing to do

		it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while (plat = FCW_Platform(it.Next()))
		{
			plat.CommonACSSetup(travelTime);

			plat.pNext = plat.pNextNext = plat.pos + plat.Vec3To(spot); //Make it portal aware in a way so TryMove() can handle it

			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (
				!dontRotate ? DeltaAngle(plat.pCurrAngs.x, spot.angle) : 0,
				!dontRotate ? DeltaAngle(plat.pCurrAngs.y, spot.pitch) : 0,
				!dontRotate ? DeltaAngle(plat.pCurrAngs.z, spot.roll) : 0);
		}
	}

	//============================
	// PlatIsActive
	//============================
	bool PlatIsActive ()
	{
		//When checking group members we only care about the origin.
		//Either "every member is active" or "every member is not active."
		let plat = self;
		if (group && group.origin)
			plat = group.origin;

		return plat.bActive;
	}

	//============================
	// IsActive (ACS utility)
	//============================
	static bool IsActive (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		let plat = FCW_Platform(it.Next());
		return (plat && plat.PlatIsActive());
	}

	//============================
	// PlatHasMoved
	//============================
	bool PlatHasMoved ()
	{
		//When checking group members we only care about the origin.
		//Either "every member has moved" or "every member has not moved."
		let plat = self;
		if (group && group.origin)
			plat = group.origin;

		return (plat.bActive && (
				plat.pos != plat.oldPos ||
				plat.angle != plat.oldAngle ||
				plat.pitch != plat.oldPitch ||
				plat.roll != plat.oldRoll) );
	}

	//============================
	// HasMoved (ACS utility)
	//============================
	static bool HasMoved (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		let plat = FCW_Platform(it.Next());
		return (plat && plat.PlatHasMoved());
	}
}
