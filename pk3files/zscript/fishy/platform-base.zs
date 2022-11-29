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

*******************************************************************************

 This is a script library containing a full-fledged, reasonably stable
 3D platform actor, a temporary answer to GZDoom's lack of "3D polyobjects".
 The platform can either be a sprite or a model.
 Though using models is the main point so it can masquerade as
 horizontally moving geometry that you can stand on and be carried by.

 In a nutshell this file contains:
 FCW_Platform - The main platform class;

 FCW_PlatformNode - a platform-centric interpolation point class
 (though GZDoom's "InterpolationPoint" is still perfectly usable);

 FCW_PlatformGroup - a class to help with the "group" logic;

 And lastly
 FCW_OldStuff_* - a measure that takes into account old
 "PathFollower" classes trying to use FCW_PlatformNode
 as well as having a interpolation path made up of
 both InterpolationPoints and FCW_PlatformNodes.

 It is recommended you replace the "FCW_" prefix to avoid conflicts with
 other people's projects.

 Regarding custom actors. Platforms can generally handle moving
 ordinary actors just fine, but if you have complex enemies/players/etc
 that are made up of multiple actors or otherwise need special treatment
 then please make use of the empty virtual functions:

 PassengerPreMove(Actor mo)
 PassengerPostMove(Actor mo, bool moved)
 SpecialBTIActor(Actor mo)

 PreMove is always called before the platform attempts to move the
 actor "mo" usually by calling TryMove().
 And PostMove is always called after "mo" was/wasn't moved.
 "moved" is set to "true" if "mo" was moved and "false" if it wasn't.

 SpecialBTIActor() is useful for actors detected during a BlockThingsIterator
 search. For cases where PassengerPre/PostMove() aren't good enough.

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
		//$Arg1Enum {1 = "Linear path / (Does nothing for non-origin group members)"; 2 = "Use point angle / Group move: Rotate angle / (ACS commands don't need this)"; 4 = "Use point pitch / Group move: Rotate pitch / (ACS commands don't need this)"; 8 = "Use point roll / Group move: Rotate roll / (ACS commands don't need this)"; 16 = "Face movement direction / (Does nothing for non-origin group members)"; 32 = "Don't clip against geometry and other platforms"; 64 = "Start active"; 128 = "Group move: Mirror group origin's movement"; 256 = "Add velocity to passengers when they jump away"; 512 = "Add velocity to passengers when stopping (and not blocked)"; 1024 = "Interpolation point is destination"; 2048 = "Resume path when activated again"; 4096 = "Always do 'crush damage' when pushing obstacles"; 8192 = "Pitch/roll changes don't affect passengers"; 16384 = "Passengers can push obstacles";}
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

		FCW_Platform.AirFriction 0.99;
		FCW_Platform.PassengerLookTics 1;
		FCW_Platform.PortalLookTics 1;
	}

	//===New flags===//
	int platFlags;
	flagdef Carriable: platFlags, 0; //Let's this platform be carried (like a passenger) by other platforms

	//===New properties===//
	double platAirFric; //For platforms that have +PUSHABLE and +NOGRAVITY. (The pre-existing 'friction' property + sector friction are for gravity bound pushables instead.)
	property AirFriction: platAirFric;

	//===New properties that are also user variables (can be set from UDB in the "Custom" tab when editing Thing)===//
	int user_passengerLookTics; //The amount of tics between searching for passengers (via BlockThingsIterator) - Set to 0 (or a negative value) to never look for passengers.
	property PassengerLookTics: user_passengerLookTics;

	int user_portalLookTics; //The amount of tics between searching for non-static line portals (via BlockLinesIterator) - Set to 0 (or a negative value) to never look for portals.
	property PortalLookTics: user_portalLookTics;

	private void HandleUserVars ()
	{
		if (bPortCopy)
		{
			user_passengerLookTics = portTwin.user_passengerLookTics;
			return;
		}

		//If these are set to 0 in UDB then use the property version. (Else use the user var version.)
		//To disable searches in UDB, set it to a negative value (eg -1).
		if (!user_passengerLookTics)
			user_passengerLookTics = default.user_passengerLookTics;
		if (!user_portalLookTics)
			user_portalLookTics = default.user_portalLookTics;
	}
}

class FCW_PlatformNode : InterpolationPoint
{
	Default
	{
		//$Title Platform Interpolation Point

		//$Arg0 Next Point
		//$Arg0Type 14
		//$Arg0Tooltip Next point must be another platform interpolation point.\n(It can't be the old interpolation point class.)

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

		for (InterpolationPoint node = self; node; node = node.next)
		{
			if (node.bVisited)
				return;
			node.bVisited = true;

			let it = level.CreateActorIterator(node.args[0], "InterpolationPoint");
			do
			{
				node.next = InterpolationPoint(it.Next());
			} while (node.next == node); //Don't link to self

			if (!node.next && node.args[0])
			{
				Console.Printf("\n\ckPlatform interpolation point with tid " .. node.tid .. " at position " ..node.pos ..
				":\n\ckcannot find next platform interpolation point with tid " .. node.args[0] .. ".");
			}
			else if (node.next && !(node.next is "FCW_PlatformNode"))
			{
				Console.Printf("\ckPlatform interpolation point with tid " .. node.tid .. " at position " ..node.pos ..
				":\n\ckis pointing at a non-platform interpolation point with tid " .. node.args[0] .. " at position " .. node.next.pos .. "\n.");
				new("FCW_OldStuff_DelayedAbort"); //For what this does, see bottom of this file
				return;
			}
		}
	}
}

//A container class for grouped platforms.
//It has an array pointing to all group members and each member points to this group.
class FCW_PlatformGroup play
{
	Array<FCW_Platform> members;
	FCW_Platform origin;	//The member that thinks for the other members when it ticks.
	FCW_Platform carrier;	//A non-member that carries one member of this group. Used for passenger theft checks.

	static FCW_PlatformGroup Create ()
	{
		let group = new("FCW_PlatformGroup");
		group.members.Clear();
		group.origin = null;
		group.carrier = null;
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

		if (!origin && otherGroup.origin)
			origin = otherGroup.origin;

		if (!carrier && otherGroup.carrier)
			carrier = otherGroup.carrier;
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
		OPTFLAG_NOPITCHROLL		= 8192,
		OPTFLAG_PASSCANPUSH		= 16384,

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

	//For PlatMove()
	enum PMoveTypes
	{
		MOVE_NORMAL = 0,
		MOVE_TELEPORT = 1,
		MOVE_QUICK = -1,
	};

	const TOP_EPSILON = 1.0; //For Z checks (if something is on top of something else)
	const ZS_EQUAL_EPSILON = 1.0 / 65536.0; //Because 'double.epsilon' is too small, we'll use 'EQUAL_EPSILON' from the source code
	const YES_BMAP = 0; //For A_ChangeLinkFlags()
	const NO_BMAP = 1;
	const EXTRA_SIZE = 20; //For line collision checking (when looking for unlinked line portals)

	vector3 oldPos;
	double oldAngle;
	double oldPitch;
	double oldRoll;
	FCW_PlatformGroup group;
	vector3 groupPos;
	double groupAngle;
	double groupPitch;
	double groupRoll;
	double time;
	double reachedTime;
	double timeFrac;
	int holdTime;
	bool bActive;
	transient bool bInMove; //No collision between a platform and its passengers during said platform's move.
	transient bool bMoved; //Used for PassengerPostMove() when everyone has finished (or tried) moving in this tic.
	InterpolationPoint currNode, firstNode;
	InterpolationPoint prevNode, firstPrevNode;
	bool bGoToNode;
	Array<Actor> passengers;
	Array<Actor> stuckActors;
	Line lastUPort;
	private FCW_Platform portTwin; //Helps with collision when dealing with unlinked line portals
	private bool bPortCopy;
	double portDelta;
	int acsFlags;
	transient int lastGetNPTime; //Make sure there's only one GetNewPassengers() blockmap search per tic
	transient bool lastGetNPResult;
	transient int lastGetUPTime; //Same deal for GetUnlinkedPortal()

	//Unlike PathFollower classes, our interpolations are done with
	//vector3 coordinates instead of checking InterpolationPoint positions.
	//This is done for 3 reasons:
	//1) Making it portal aware.
	//2) Can be arbitrarily set through ACS (See utility functions below).
	//3) If following a path, can course correct itself after being pushed or carried by another platform.
	vector3 pCurr, pPrev, pNext, pNextNext; //Positions in the world.
	vector3 pCurrAngs, pPrevAngs, pNextAngs, pNextNextAngs; //X = angle, Y = pitch, Z = roll.

	//============================
	// BeginPlay (override)
	//============================
	override void BeginPlay ()
	{
		// Change the statnum so that platforms tick
		// after every door/crusher/lift etc has ticked.
		// Please note that this has the subtle side effect of
		// also ticking after every non-platform actor
		// has ticked.
		//
		// Changing the statnum along with calling FindFloorCeiling()
		// in the CheckFloorCeiling() function is a workaround to
		// make a platform move with a ceiling/3D floor that's pushing it up/down
		// and not clip through it as the ceiling/3D floor moves.
		// If we don't change the statnum then a platform being pushed up/down
		// would appear to be partially stuck inside the ceiling/3D floor
		// as it moves.
		//
		// Feel free to comment-out or remove this if it's causing
		// problems for you and you don't have platforms that get
		// in the way of moving ceilings or 3D floors.
		ChangeStatNum(STAT_SECTOREFFECT + 1);

		oldPos = pos;
		oldAngle = angle;
		oldPitch = pitch;
		oldRoll = roll;
		group = null;
		groupPos = pos;
		groupAngle = angle;
		groupPitch = pitch;
		groupRoll = roll;
		time = 1.1;
		reachedTime = 0;
		timeFrac = 0;
		holdTime = 0;
		bActive = false;
		bInMove = false;
		bMoved = false;
		currNode = firstNode = null;
		prevNode = firstPrevNode = null;
		bGoToNode = false;
		passengers.Clear();
		stuckActors.Clear();
		lastUPort = null;
		portTwin = null;
		bPortCopy = false;
		portDelta = 0;
		acsFlags = 0;
		lastGetNPTime = -1;
		lastGetNPResult = false;
		lastGetUPTime = -1;

		pCurr = pPrev = pNext = pNextNext = (0, 0, 0);
		pCurrAngs = pPrevAngs = pNextAngs = pNextNextAngs = (0, 0, 0);
	}

	//============================
	// PostBeginPlay (override)
	//============================
	override void PostBeginPlay ()
	{
		Super.PostBeginPlay();
		HandleUserVars();
		if (bPortCopy)
			return;

		bool noPrefix = (args[ARG_GROUPTID] && !SetUpGroup(args[ARG_GROUPTID], false));

		//If the group origin is already active then call PlatMove() here to move us
		//along with the rest of the group. This matters if the origin's first
		//interpolation point has a defined hold time because depending on who ticks first
		//some members might have already moved and some might have not.
		if (group && group.origin)
		{
			let ori = group.origin;
			if (ori.pos != ori.groupPos ||
				ori.angle != ori.groupAngle ||
				ori.pitch != ori.groupPitch ||
				ori.roll != ori.groupRoll)
			{
				ori.PlatMove(ori.pos, ori.angle, ori.pitch, ori.roll, MOVE_TELEPORT);
			}
		}

		//In case the mapper placed walking monsters on the platform
		//get something for HandleOldPassengers() to monitor.
		GetNewPassengers(true);

		//Print no (additional) warnings if we're not supposed to have a interpolation point
		if (!args[ARG_NODETID])
			return;

		if (!SetUpPath(args[ARG_NODETID], noPrefix))
			return;

		if (args[ARG_OPTIONS] & OPTFLAG_STARTACTIVE)
			Activate(self);
	}

	//============================
	// SetUpPath
	//============================
	private bool SetUpPath (int nodeTid, bool noPrefix)
	{
		String prefix = noPrefix ? "" : "\n\ckPlatform class '" .. GetClassName() .. "' with tid " .. tid .. " at position " .. pos .. ":\n";
		let it = level.CreateActorIterator(nodeTid, "InterpolationPoint");
		firstNode = InterpolationPoint(it.Next());
		if (!firstNode)
		{
			Console.Printf(prefix .. "\ckCan't find interpolation point with tid " .. nodeTid .. ".");
			return false;
		}

		//Verify the path has enough nodes
		if (firstNode is "FCW_PlatformNode")
		{
			FCW_PlatformNode(firstNode).PNodeFormChain();
		}
		else
		{
			firstNode.FormChain();
			FCW_OldStuff_Common.CheckNodeTypes(firstNode); //The old nodes shouldn't point to platform nodes
		}

		bool optGoToNode = (args[ARG_OPTIONS] & OPTFLAG_GOTONODE);

		if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
		{
			//Linear path; need 2 nodes unless the first node is the destination
			if (!optGoToNode && !firstNode.next)
			{
				Console.Printf(prefix .. "\ckPath needs at least 2 nodes. (Interpolation point tid: " .. nodeTid .. ".)");
				return false;
			}
		}
		else //Spline path; need 4 nodes unless the first node is the destination
		{
			if (!optGoToNode && (
				!firstNode.next ||
				!firstNode.next.next ||
				!firstNode.next.next.next) )
			{
				Console.Printf(prefix .. "\ckPath needs at least 4 nodes. (Interpolation point tid: " .. nodeTid .. ".)");
				return false;
			}

			//In case the first node isn't the destination.
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
			else if (!optGoToNode)
			{
				firstPrevNode = firstNode;
				firstNode = firstNode.next;
			}
		}
		return true;
	}

	//============================
	// SetUpGroup
	//============================
	private bool SetUpGroup (int otherPlatTid, bool doUpdateGroupInfo)
	{
		let it = level.CreateActorIterator(otherPlatTid, "FCW_Platform");
		FCW_Platform plat;
		Array<FCW_Platform> newMembers;
		bool foundOne = false;
		while (plat = FCW_Platform(it.Next()))
		{
			if (plat != self)
				foundOne = true;

			if (plat.group) //Target is in its own group?
			{
				if (!group) //We don't have a group?
				{
					newMembers.Push(self);
					plat.group.Add(self);
				}
				else if (plat.group != group) //Both are in different groups?
				{
					newMembers.Append(group.members);
					plat.group.MergeWith(group);
				}
				//else - nothing happens because it's the same group or plat == self
			}
			else if (group) //We're in a group but target doesn't have a group?
			{
				newMembers.Push(plat);
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
			Console.Printf("\n\ckPlatform class '" .. GetClassName() .. "' with tid " .. tid .. " at position " .. pos ..
				":\n\ckCan't find platform(s) with tid " .. otherPlatTid .. " to group with.");
			return false;
		}

		if (!doUpdateGroupInfo)
			return true;

		let ori = group.origin;
		if (!ori)
		for (int i = 0; i < group.members.Size(); ++i)
		{
			//With no designated origin, just update everyone's
			//group info to where they are.
			plat = group.GetMember(i);
			if (plat)
			{
				plat.groupPos = plat.pos;
				plat.groupAngle = plat.angle;
				plat.groupPitch = plat.pitch;
				plat.groupRoll = plat.roll;
			}
		}
		else if (newMembers.Size())
		{
			//Only set up the new members' group info relative
			//to the origin.
			for (int i = 0; i < newMembers.Size(); ++i)
			{
				plat = newMembers[i];
				if (plat)
					plat.UpdateGroupInfo();
			}
		}
		return true;
	}

	//============================
	// UpdateGroupInfo
	//============================
	private void UpdateGroupInfo ()
	{
		//This is similar to MoveGroup() but backwards
		let ori = group.origin;
		double delta = DeltaAngle(ori.angle, ori.groupAngle);
		double piDelta = DeltaAngle(ori.pitch, ori.groupPitch);
		double roDelta = DeltaAngle(ori.roll, ori.groupRoll);

		if (args[ARG_OPTIONS] & OPTFLAG_MIRROR)
		{
			vector3 offset = level.Vec3Diff(ori.groupPos, ori.pos);
			groupPos = level.Vec3Offset(pos, offset);

			groupAngle = angle - delta;
			groupPitch = pitch - piDelta;
			groupRoll = roll - roDelta;
		}
		else //Set up for proper orbiting
		{
			vector3 offset = level.Vec3Diff(ori.pos, pos);
			offset = RotateVector3(offset, delta, piDelta, roDelta, ori.groupAngle, true);
			groupPos = level.Vec3Offset(ori.groupPos, offset);

			groupAngle = angle + delta;
			double diff = DeltaAngle(ori.groupAngle, groupAngle);
			double c = cos(diff), s = sin(diff);

			groupPitch = pitch + piDelta*c - roDelta*s;
			groupRoll = roll + piDelta*s + roDelta*c;
		}
	}

	//============================
	// RotateVector3
	//============================
	static vector3 RotateVector3 (vector3 vec, double yDelta, double pDelta, double rDelta, double baseAngle, bool backward)
	{
		//Used by MoveGroup()   where backward == false
		//and UpdateGroupInfo() where backward == true.

		double cFirst = cos(-baseAngle), sFirst = sin(-baseAngle);
		double cY = cos(yDelta), sY = sin(yDelta);
		double cP = cos(pDelta), sP = sin(pDelta);
		double cR = cos(rDelta), sR = sin(rDelta);
		double cLast = cos(baseAngle), sLast = sin(baseAngle);

		vec.xy = (vec.x*cFirst - vec.y*sFirst, vec.x*sFirst + vec.y*cFirst); //Rotate to 0 angle
		if (backward)
		{
			vec = (vec.x*cY - vec.y*sY, vec.x*sY + vec.y*cY, vec.z);  //Z axis (yaw/angle)
			vec = (vec.x*cP + vec.z*sP, vec.y, -vec.x*sP + vec.z*cP); //Y axis (pitch)
			vec = (vec.x, vec.y*cR - vec.z*sR, vec.y*sR + vec.z*cR);  //X axis (roll)
		}
		else
		{
			vec = (vec.x, vec.y*cR - vec.z*sR, vec.y*sR + vec.z*cR);  //X axis (roll)
			vec = (vec.x*cP + vec.z*sP, vec.y, -vec.x*sP + vec.z*cP); //Y axis (pitch)
			vec = (vec.x*cY - vec.y*sY, vec.x*sY + vec.y*cY, vec.z);  //Z axis (yaw/angle)
		}
		vec.xy = (vec.x*cLast - vec.y*sLast, vec.x*sLast + vec.y*cLast); //Rotate back to 'baseAngle'

		return vec;
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

		if (bInMove || (portTwin && portTwin.bInMove))
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
	static bool FitsAtPosition (Actor mo, vector3 testPos, bool ignoreActors = false)
	{
		//Unlike TestMobjLocation(), CheckMove() takes into account
		//actors that have the flags FLOORHUGGER, CEILINGHUGGER
		//and CANTLEAVEFLOORPIC.

		let oldThruActors = mo.bThruActors;
		if (ignoreActors)
			mo.bThruActors = true; //Makes P_CheckPosition() not iterate through the thing blockmap; it skips calling PIT_CheckThing()
		let oldZ = mo.pos.z;
		mo.SetZ(testPos.z); //Because setting Z has an effect on CheckMove()'s outcome

		FCheckPosition tm;
		bool result = (mo.CheckMove(testPos.xy, 0, tm) &&
			testPos.z >= tm.floorZ &&				//This is something that TestMobjLocation() checks
			testPos.z + mo.height <= tm.ceilingZ);	//and that CheckMove() does not account for.

		mo.bThruActors = oldThruActors;
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
	// PushObstacle
	//============================
	private void PushObstacle (Actor pushed, vector3 pushForce)
	{
		if ((bCannotPush && stuckActors.Find(pushed) >= stuckActors.Size() ) || //Can't push it if we have CANNOTPUSH and this isn't an actor that's stuck in us.
			(!pushed.bPushable && //Always push actors that have PUSHABLE.
			(pushed.bDontThrust || pushed is "FCW_Platform") ) ) //Otherwise, only push it if it's a non-platform and doesn't have DONTTHRUST.
		{
			pushForce = (0, 0, 0);
		}
		else if (!OverlapXY(self, pushed)) //Out of XY range?
		{
			pushForce.z = 0;
		}
		else
		{
			bool minForce = false;
			if (pushForce.xy ~== (0, 0))
			{
				pushForce.x = 0.2;
				minForce = true;
			}

			double delta = DeltaAngle(VectorAngle(pushForce.x, pushForce.y), AngleTo(pushed));
			if (minForce || delta > 90 || delta < -90)
				pushForce.xy = RotateVector(pushForce.xy, delta); //Push away from platform's center
		}

		//Don't accept close-to-zero velocity.
		//And don't apply 'pushForce' if the obstacle's velocity speed is equal to or exceeds the 'pushForce' in a particular direction.
		if (pushForce.x ~== 0 || (pushForce.x < 0 && pushed.vel.x <= pushForce.x) || (pushForce.x > 0 && pushed.vel.x >= pushForce.x)) pushForce.x = 0;
		if (pushForce.y ~== 0 || (pushForce.y < 0 && pushed.vel.y <= pushForce.y) || (pushForce.y > 0 && pushed.vel.y >= pushForce.y)) pushForce.y = 0;
		if (pushForce.z ~== 0 || (pushForce.z < 0 && pushed.vel.z <= pushForce.z) || (pushForce.z > 0 && pushed.vel.z >= pushForce.z)) pushForce.z = 0;

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
		//Take into account angle changes when
		//passing through non-static line portals.
		//All checked angles have to be adjusted.
		if (prevNode && !bGoToNode)
		{
			//'pPrev' has to be adjusted if 'currNode' position is different from platform's.
			//Which can happen because of non-static line portals or because of velocity movement.
			vector3 offset = currNode ? currNode.Vec3To(self) : (0, 0, 0);
			pPrev = pos + Vec3To(prevNode) + offset; //Make it portal aware in a way so TryMove() can handle it
			pPrevAngs = (
			Normalize180(prevNode.angle + portDelta),
			Normalize180(prevNode.pitch),
			Normalize180(prevNode.roll));
		}

		pCurr = pos;
		if (!prevNode || bGoToNode)
		{
			pCurrAngs = (
			Normalize180(angle),
			Normalize180(pitch),
			Normalize180(roll));
		}
		else
		{
			pCurrAngs = pPrevAngs + (
			DeltaAngle(pPrevAngs.x, angle),
			DeltaAngle(pPrevAngs.y, pitch),
			DeltaAngle(pPrevAngs.z, roll));
		}

		if (currNode && (currNode.next || bGoToNode))
		{
			InterpolationPoint nextNode = bGoToNode ? currNode : currNode.next;

			pNext = pos + Vec3To(nextNode); //Make it portal aware in a way so TryMove() can handle it
			pNextAngs = pCurrAngs + (
			DeltaAngle(pCurrAngs.x, nextNode.angle + portDelta),
			DeltaAngle(pCurrAngs.y, nextNode.pitch),
			DeltaAngle(pCurrAngs.z, nextNode.roll));

			if (nextNode.next)
			{
				pNextNext = pos + Vec3To(nextNode.next); //Make it portal aware in a way so TryMove() can handle it
				pNextNextAngs = pNextAngs + (
				DeltaAngle(pNextAngs.x, nextNode.next.angle + portDelta),
				DeltaAngle(pNextAngs.y, nextNode.next.pitch),
				DeltaAngle(pNextAngs.z, nextNode.next.roll));
			}
			else //No nextNode.next
			{
				pNextNext = pNext;
				pNextNextAngs = pNextAngs;
			}
		}

		if (!currNode || (!currNode.next && !bGoToNode))
		{
			pNextNext = pNext = pCurr;
			pNextNextAngs = pNextAngs = pCurrAngs;
		}

		if (!prevNode || bGoToNode)
		{
			pPrev = pCurr;
			pPrevAngs = pCurrAngs;
		}
	}

	//============================
	// AdjustInterpolationCoordinates
	//============================
	private void AdjustInterpolationCoordinates (vector3 startPos, vector3 endPos, double delta)
	{
		//Used for when crossing portals
	
		//Offset and possibly rotate the coordinates
		pPrev -= startPos;
		pCurr -= startPos;
		pNext -= startPos;
		pNextNext -= startPos;

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
		pPrev += endPos;
		pCurr += endPos;
		pNext += endPos;
		pNextNext += endPos;
	}

	//============================
	// IsCarriable
	//============================
	bool IsCarriable (Actor mo)
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

		let plat = FCW_Platform(mo);
		if (plat)
		{
			if (!plat.bCarriable)
				return false;

			//If either one has this option then don't carry it
			if ((args[ARG_OPTIONS] | plat.args[ARG_OPTIONS]) & OPTFLAG_IGNOREGEO)
				return false;

			//Don't carry platform if it's in our group
			if (group && plat.group && group == plat.group)
				return false;

			//If this is somebody's portal copy, ignore it
			if (plat.bPortCopy)
				return false;

			//A platform in move is the platform that's likely carrying us, ignore it
			if (plat.bInMove || (plat.portTwin && plat.portTwin.bInMove) )
				return false;
		}
		return true;
	}

	//============================
	// CanStealFrom
	//============================
	bool CanStealFrom (FCW_Platform other, Actor mo)
	{
		double myTop = pos.z + height;
		double otherTop = other.pos.z + other.height;

		if (myTop > otherTop)
			return true;

		if (!group || group != other.group || myTop < otherTop)
			return false;

		//'other' is a groupmate with the same top
		return (mo &&
			((args[ARG_OPTIONS] ^ other.args[ARG_OPTIONS]) & OPTFLAG_MIRROR) &&   //Only steal if we have different "mirror" flag settings and
			OverlapXY(self, mo, radius) && !OverlapXY(other, mo, other.radius) ); //'mo' is within our radius and NOT within other's radius.
	}

	//============================
	// ForgetPassenger
	//============================
	private void ForgetPassenger (int index)
	{
		let plat = FCW_Platform(passengers[index]);
		if (plat && plat.group && plat.group.carrier == self)
			plat.group.carrier = null;
		passengers.Delete(index);
	}

	//============================
	// PassengerPreMove
	//============================
	virtual void PassengerPreMove (Actor mo)
	{
		// This is called every time before a (potential) passenger (called 'mo')
		// is moved.
	}

	//============================
	// PassengerPostMove
	//============================
	virtual void PassengerPostMove (Actor mo, bool moved)
	{
		// This is called every time after a (potential) passenger (called 'mo')
		// was tried to be moved.
		//
		// 'moved' will be true if 'mo' was moved successfully,
		// otherwise it will be false.
		//
		// The distinction is useful if you want to run code only if the
		// passenger (mo) was moved or not moved.
	}

	//============================
	// SpecialBTIActor
	//============================
	virtual bool SpecialBTIActor (Actor mo)
	{
		// Use this to handle special actors that aren't being pointed by passengers
		// (and thus can't be handled in the PassengerPre/PostMove() functions)
		// but can still be detected in a BlockThingsIterator (BTI) search.
		//
		// Return 'true' if the actor shouldn't be processed
		// and skip to the next blockmap result.
		//
		// Or return 'false' to run the usual checks in
		// GetNewPassengers() and GetStuckActors().
		// The "usual checks" being:
		// Is it within XY and Z range, is it a corpse,
		// is it solid, is it carriable, is it a stuck actor, etc, etc.
		//
		// Important note: because this is called during a BTI search
		// please don't spawn/destroy actors here because that tends to
		// mess up the iterator.
		return false;
	}

	//============================
	// GetNewPassengers
	//============================
	private bool GetNewPassengers (bool ignoreObs, bool ignoreTicRate = false)
	{
		// In addition to fetching passengers, this is where corpses get crushed, too. Items won't get destroyed.
		// Returns false if one or more actors are completely stuck inside platform unless 'ignoreObs' is true.

		if (lastGetNPTime == level.mapTime)
			return lastGetNPResult; //Already called in this tic
		lastGetNPTime = level.mapTime;

		if (user_passengerLookTics <= 0 || //Passenger, stuck actor, and corpse blockmap searching is disabled?
			(!ignoreObs && !ignoreTicRate && (level.mapTime % user_passengerLookTics) ) ) //'ignoreObs' is used in "tele moves"; those shouldn't skip searching.
		{
			lastGetNPResult = true;
			return true;
		}

		double top = pos.z + height;
		Array<Actor> miscActors; //The actors on top of or stuck inside confirmed passengers (We'll move those, too)
		Array<Actor> newPass; //Potential new passengers, usually (but not always) detected on top of us
		Array<Actor> tryZFix, tryZFixItems;
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

			if (SpecialBTIActor(mo))
				continue; //Already handled

			if (mo == self || mo == portTwin)
				continue;

			let plat = FCW_Platform(mo);
			if (plat)
				otherPlats.Push(plat);

			bool oldPass = (passengers.Find(mo) < passengers.Size());
			bool canCarry = ((!portTwin || portTwin.passengers.Find(mo) >= portTwin.passengers.Size()) && //Don't take your twin's passengers here
						IsCarriable(mo));

			//Check XY overlap
			double blockDist = radius + mo.radius;
			if (abs(it.position.x - mo.pos.x) < blockDist && abs(it.position.y - mo.pos.y) < blockDist)
			{
				if (plat && (plat.bInMove || (plat.portTwin && plat.portTwin.bInMove) ) ) //This is probably the platform that's carrying/moving us
				{
					if (!ignoreObs && !bOnMobj &&
						(abs(pos.z - (mo.pos.z + mo.height)) <= TOP_EPSILON || //Are we standing on 'mo'?
						OverlapZ(self, mo) ) )
					{
						bOnMobj = true;
					}
					continue;
				}

				//'ignoreObs' makes anything above our 'top' legit unless there's a 3D floor in the way.
				if (mo.pos.z >= top - TOP_EPSILON && (ignoreObs || mo.pos.z <= top + TOP_EPSILON) && //On top of us?
					mo.floorZ <= top + TOP_EPSILON) //No 3D floor above our 'top' that's below 'mo'?
				{
					if (canCarry && !oldPass)
						newPass.Push(mo);
					continue;
				}

				if (OverlapZ(self, mo))
				{
					if (mo.bCorpse && !mo.bDontGib && mo.tics == -1) //Let dying actors finish their death sequence
					{
						if (!ignoreObs)
							corpses.Push(mo);
					}
					else if (CollisionFlagChecks(self, mo) &&
						self.CanCollideWith(mo, false) && mo.CanCollideWith(self, true) )
					{
						//Try to correct 'mo' Z so it can ride us, too.
						//But only if its 'maxStepHeight' allows it.
						if (canCarry && top - mo.pos.z <= mo.maxStepHeight)
						{
							tryZFix.Push(mo);
						}
						else if (!ignoreObs)
						{
							result = false;
							bOnMobj = true;
							if (stuckActors.Find(mo) >= stuckActors.Size())
								stuckActors.Push(mo);
						}
					}
					else if (mo is "Inventory" && mo.bSpecial) //Item that can be picked up?
					{
						//Try to correct 'mo' Z so it can ride us, too.
						//But only if its 'maxStepHeight' allows it.
						if (canCarry && top - mo.pos.z <= mo.maxStepHeight)
							tryZFixItems.Push(mo);
					}
					continue;
				}

				if (!ignoreObs && !bOnMobj &&
					abs(pos.z - (mo.pos.z + mo.height)) <= TOP_EPSILON && //Are we standing on 'mo'?
					CollisionFlagChecks(self, mo) &&
					self.CanCollideWith(mo, false) && mo.CanCollideWith(self, true) )
				{
					bOnMobj = true;
				}
			}

			if (canCarry && !oldPass && mo.bOnMobj)
				miscActors.Push(mo); //We'll compare this later against the passengers
		}

		//Try to stand on the highest stuck actor if our 'maxStepHeight' allows it
		Actor highestMo = null;
		if (!ignoreObs)
		for (int i = 0; i < stuckActors.Size(); ++i)
		{
			let mo = stuckActors[i];
			if (!mo)
				continue;

			if (!highestMo || highestMo.pos.z + highestMo.height < mo.pos.z + mo.height)
				highestMo = mo;
		}

		double moTop;
		if (highestMo && (moTop = highestMo.pos.z + highestMo.height) - pos.z <= maxStepHeight &&
			FitsAtPosition(self, (pos.xy, moTop), true))
		{
			PlatMove((pos.xy, moTop), angle, pitch, roll, MOVE_QUICK);
			top = pos.z + height;
			stuckActors.Delete(stuckActors.Find(highestMo));
			result = true;
		}

		for (int i = 0; i < tryZFix.Size(); ++i)
		{
			let mo = tryZFix[i];
			PassengerPreMove(mo);
			bool fits = FitsAtPosition(mo, (mo.pos.xy, top), true);
			if (fits)
			{
				if (mo is "FCW_Platform")
				{
					FCW_Platform(mo).PlatMove((mo.pos.xy, top), mo.angle, mo.pitch, mo.roll, MOVE_QUICK);
				}
				else
				{
					mo.SetZ(top);
					mo.CheckPortalTransition(); //Handle sector portals properly
				}

				if (passengers.Find(mo) >= passengers.Size())
					newPass.Push(mo);
			}
			else if (!ignoreObs)
			{
				result = false;
				bOnMobj = true;
				if (stuckActors.Find(mo) >= stuckActors.Size())
					stuckActors.Push(mo);
			}
			PassengerPostMove(mo, fits);
		}

		for (int i = 0; i < tryZFixItems.Size(); ++i)
		{
			let mo = tryZFixItems[i];
			PassengerPreMove(mo);
			bool fits = FitsAtPosition(mo, (mo.pos.xy, top), true);
			if (fits)
			{
				mo.SetZ(top);
				mo.CheckPortalTransition(); //Handle sector portals properly
				if (passengers.Find(mo) >= passengers.Size())
					newPass.Push(mo);
			}
			PassengerPostMove(mo, fits);
		}

		for (int i = 0; i < corpses.Size(); ++i)
			corpses[i].Grind(false);

		if (newPass.Size() || miscActors.Size())
		{
			//Take into account the possibility that not all
			//group members can be found in a blockmap search.
			if (group)
			for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
			{
				let plat = group.GetMember(iPlat);
				if (plat && plat != self && otherPlats.Find(plat) >= otherPlats.Size())
					otherPlats.Push(plat);
			}

			//Go through the other detected platforms (and our groupmates)
			//and see if we can steal some of their passengers.
			for (int iPlat = 0; (newPass.Size() || miscActors.Size()) && iPlat < otherPlats.Size(); ++iPlat)
			{
				let plat = otherPlats[iPlat];
				if (!plat.passengers.Size())
					continue;

				for (int i = 0; i < newPass.Size(); ++i)
				{
					let index = plat.passengers.Find(newPass[i]);
					if (index < plat.passengers.Size())
					{
						if (CanStealFrom(plat, newPass[i]))
							plat.ForgetPassenger(index);
						else
							newPass.Delete(i--);
					}
				}
				for (int i = 0; i < miscActors.Size(); ++i)
				{
					if (plat.passengers.Find(miscActors[i]) < plat.passengers.Size())
						miscActors.Delete(i--);
				}
			}
			passengers.Append(newPass);

			//Now figure out which of the misc actors are on top of/stuck inside
			//established passengers.
			for (int i = 0; miscActors.Size() && i < passengers.Size(); ++i)
			{
				let mo = passengers[i];
				if (!mo)
				{
					ForgetPassenger(i--);
					continue;
				}
				moTop = mo.pos.z + mo.height;

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
		}

		//If we have passengers that are grouped platforms,
		//prune 'passengers' array; we only want one member per group.
		//Preferably the origin if active, else the closest member.
		Array<FCW_PlatformGroup> otherGroups;
		for (int i = 0; i < passengers.Size(); ++i)
		{
			let plat = FCW_Platform(passengers[i]);
			if (!plat || !plat.group)
				continue;

			if (otherGroups.Find(plat.group) < otherGroups.Size())
			{
				passengers.Delete(i--); //Already dealt with this group
				continue;
			}
			otherGroups.Push(plat.group);

			//Since we are dealing with groups it is likely the 'carrier'
			//is outside of the blockmap search. That's why it's a pointer
			//in the group class.
			if (plat.group.carrier && plat.group.carrier != self)
			{
				if (!CanStealFrom(plat.group.carrier, null))
				{
					passengers.Delete(i--); //Can't take any of this group's members
					continue;
				}

				//Make group cut ties with current carrier before self becomes the new carrier
				let carrier = plat.group.carrier;
				for (int iMember = 0; carrier.passengers.Size() && iMember < plat.group.members.Size(); ++iMember)
				{
					let member = plat.group.GetMember(iMember);
					if (!member)
						continue;

					int index = carrier.passengers.Find(member);
					if (index < carrier.passengers.Size())
						carrier.passengers.Delete(index);
				}
			}
			plat.group.carrier = self;

			if (plat.group.origin && plat.group.origin.bActive)
			{
				passengers[i] = plat.group.origin;
				continue;
			}

			//No active origin, so pick the closest member.
			double dist = Distance3D(plat);
			for (int iMember = 0; iMember < plat.group.members.Size(); ++iMember)
			{
				let member = plat.group.GetMember(iMember);
				if (member && member != plat)
				{
					double thisDist = Distance3D(member);
					if (thisDist < dist)
					{
						dist = thisDist;
						passengers[i] = member;
					}
				}
			}
			plat.group.origin = FCW_Platform(passengers[i]);
		}
		lastGetNPResult = result;
		return result;
	}

	//============================
	// MustGetNewPassengers
	//============================
	private void MustGetNewPassengers ()
	{
		//For cases where the search tic rate must be ignored.
		//(Handle portal twin and groupmates, too.)
		GetNewPassengers(false, true);
		if (portTwin)
			portTwin.GetNewPassengers(false, true);

		if (group)
		for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
		{
			let plat = group.GetMember(iPlat);
			if (plat && plat != self)
			{
				plat.GetNewPassengers(false, true);
				if (plat.portTwin)
					plat.portTwin.GetNewPassengers(false, true);
			}
		}
	}

	//============================
	// MovePassengers
	//============================
	private bool MovePassengers (vector3 startPos, vector3 endPos, double forward, double delta, double piDelta, double roDelta, bool teleMove)
	{
		// Returns false if a blocked passenger would block the platform's movement unless 'teleMove' is true.
		//
		// By the time this is called, all passengers will
		// have been excluded from the blockmap in PlatMove().
		// That is done so they can all move at once
		// without colliding with each other.
		//
		// If a passenger can't fit at its new position
		// it will be linked back into the blockmap in this function,
		// PassengerPostMove() will be called with 'moved' set to false,
		// and the passenger will get removed from the 'passengers' array.
		// Else they'll be linked back in PlatMove().

		if (!passengers.Size())
			return true; //No passengers? Nothing to do

		//Move our passengers (platform rotation is taken into account)
		double top = endPos.z + height;
		double c = cos(delta), s = sin(delta);
		vector2 piAndRoOffset = (0, 0);
		if ((piDelta || roDelta) && !(args[ARG_OPTIONS] & OPTFLAG_NOPITCHROLL))
		{
			piDelta *= 2;
			roDelta *= 2;
			piAndRoOffset = (cos(forward)*piDelta, sin(forward)*piDelta) + //Front/back
				(cos(forward-90)*roDelta, sin(forward-90)*roDelta); //Right/left
		}

		vector3 pushForce = level.Vec3Diff(startPos, endPos);
		Array<double> preMovePos; //Sadly we can't have a vector2/3 dyn array
		for (int i = 0; i < passengers.Size(); ++i)
		{
			let mo = passengers[i];
			let moOldPos = mo.pos;
			let moOldNoDropoff = mo.bNoDropoff;
			let plat = FCW_Platform(mo);

			vector3 offset = level.Vec3Diff(startPos, moOldPos);
			if (delta) //Will 'offset' get rotated?
			{
				double oldOffX = offset.x;
				double oldOffY = offset.y;
				double maxDist = radius + mo.radius;

				offset.xy = (offset.x*c - offset.y*s, offset.x*s + offset.y*c); //Rotate it

				//If this passenger is currently within XY range then clamp the rotated offset
				//so that the passenger doesn't end up outside the XY range at its new position
				//and potentially fall off the platform.
				//This is a workaround to the fact that GZDoom (at this moment in time)
				//does not rotate an actor's bounding box when said actor's angle/yaw changes.
				if (abs(oldOffX) < maxDist && abs(oldOffY) < maxDist)
				{
					maxDist -= 1.0;
					offset.x = clamp(offset.x, -maxDist, maxDist);
					offset.y = clamp(offset.y, -maxDist, maxDist);
				}
			}
			offset.xy += piAndRoOffset; //Platform pitch/roll changes may still make passengers fall off; that's intentional

			//No tele move means absolute offset; it needs to be absolute so TryMove() works as expected.
			//Because TryMove() has its own handling of crossing line portals.
			vector3 moNewPos = level.Vec3Offset(endPos, offset, !teleMove);

			//Handle z discrepancy
			if (moNewPos.z < top && moNewPos.z + mo.height >= top)
				moNewPos.z = top;

			bool moved;
			if (plat)
			{
				mo.bNoDropoff = false;
				let moOldAngle = mo.angle;
				let moNewAngle = mo.angle + delta;
				int result = plat.PlatMove(moNewPos, moNewAngle, mo.pitch, mo.roll, teleMove);
				moved = (result == 2); //2 == this plat and its groupmates moved. 1 == plat moved but not all groupmates moved.
				if (plat.bActive)
				{
					//Tried to move an active platform.
					//If we moved it, adjust its
					//interpolation coordinates.
					if (result)
					{
						vector3 diff = level.Vec3Diff(moOldPos, mo.pos);
						plat.pPrev += diff;
						plat.pCurr += diff;
						if (moNewPos != mo.pos)
							plat.AdjustInterpolationCoordinates(moNewPos, mo.pos, DeltaAngle(moNewAngle, mo.angle));
					}

					//In the unlikely event the plat has one of the flags CANPUSHWALLS, CANUSEWALLS, ACTIVATEMCROSS or ACTIVATEPCROSS
					//and gets Thing_Remove()'d by activating a line.
					if (mo && !mo.bDestroyed)
					{
						mo.bNoDropoff = moOldNoDropoff;
						mo.A_ChangeLinkFlags(YES_BMAP);
						PassengerPostMove(mo, result);
					}
					ForgetPassenger(i--); //Forget this active platform (we won't move it back in case something gets blocked)
					continue;
				}

				if (!mo || mo.bDestroyed)
				{
					ForgetPassenger(i--);
					continue;
				}
				mo.bNoDropoff = moOldNoDropoff;
				mo.angle = moOldAngle; //The angle change is supposed to happen later
			}
			else if (teleMove)
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
				//NOTE: This was based on similar code from P_XYMovement().
				double maxMove = max(1, mo.radius - 1);
				double moveSpeed = max(abs(stepMove.x), abs(stepMove.y));
				if (moveSpeed > maxMove)
				{
					maxSteps = int(1 + moveSpeed / maxMove);
					stepMove /= maxSteps;
				}

				//NODROPOFF overrides TryMove()'s second argument,
				//but the passenger should be treated like a flying object.
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
					ForgetPassenger(i--);
					continue;
				}
				mo.bNoDropoff = moOldNoDropoff;
			}

			if (moved)
			{
				if (!teleMove)
				{
					//Only remember the old position if 'mo' was moved.
					//(Else we delete the 'passengers' entry containing 'mo', see below.)
					preMovePos.Push(moOldPos.x);
					preMovePos.Push(moOldPos.y);
					preMovePos.Push(moOldPos.z);
				}
			}
			else
			{
				if (mo.pos != moOldPos)
				{
					if (!plat)
						mo.SetOrigin(moOldPos, true);
					else
						plat.PlatMove(moOldPos, mo.angle, mo.pitch, mo.roll, MOVE_TELEPORT);
				}

				//This passenger will be 'solid' for the others
				mo.A_ChangeLinkFlags(YES_BMAP);
				PassengerPostMove(mo, false);
				ForgetPassenger(i--);

				if (teleMove)
					continue;

				//Optionally have passengers push away obstacles.
				//(No need if this passenger is a platform because
				//being a platform it already pushed an obstacle.)
				if (!plat && !mo.bCannotPush && (args[ARG_OPTIONS] & OPTFLAG_PASSCANPUSH))
				{
					let oldCannotPush = bCannotPush;
					bCannotPush = false;

					if (mo.blockingMobj)
						PushObstacle(mo.blockingMobj, pushForce);

					bCannotPush = oldCannotPush;
				}

				Array<Actor> movedBack = { mo };
				for (int iMovedBack = 0; iMovedBack < movedBack.Size(); ++iMovedBack)
				{
					mo = movedBack[iMovedBack];

					//See if this 'mo' would block the platform
					let realPos = pos;
					SetXYZ(endPos);
					bool blocked = (CollisionFlagChecks(self, mo) &&
							OverlapZ(self, mo) && //Within Z range?
							OverlapXY(self, mo) && //Within XY range?
							self.CanCollideWith(mo, false) && mo.CanCollideWith(self, true) );
					SetXYZ(realPos);

					//See if the ones we moved already will collide with this one
					//and if yes, move them back to their old positions.
					//(If the platform's "blocked" then move everyone back unconditionally.)
					for (int iOther = 0; iOther <= i; ++iOther)
					{
						let otherMo = passengers[iOther];
						if (!blocked && ( !CollisionFlagChecks(otherMo, mo) ||
							!OverlapZ(otherMo, mo) || //Out of Z range?
							!OverlapXY(otherMo, mo) || //Out of XY range?
							!otherMo.CanCollideWith(mo, false) || !mo.CanCollideWith(otherMo, true) ) )
						{
							continue;
						}

						//Put 'otherMo' back at its old position
						vector3 otherOldPos = (preMovePos[iOther*3], preMovePos[iOther*3 + 1], preMovePos[iOther*3 + 2]);
						plat = FCW_Platform(otherMo);
						if (!plat)
							otherMo.SetOrigin(otherOldPos, true);
						else
							plat.PlatMove(otherOldPos, mo.angle, mo.pitch, mo.roll, MOVE_TELEPORT);

						otherMo.A_ChangeLinkFlags(YES_BMAP);
						PassengerPostMove(otherMo, false);
						preMovePos.Delete(iOther*3, 3);
						ForgetPassenger(iOther--);
						i--;

						if (!blocked)
						{
							movedBack.Push(otherMo);
							otherMo.blockingMobj = mo;
						}
					}

					if (blocked)
					{
						PushObstacle(mo, pushForce);
						if (!(mo is "FCW_Platform") && mo != movedBack[0]) //We (potentially) already pushed/crushed the first one's blocker
						{
							//'OPTFLAG_PASSCANPUSH' doesn't matter here since it's considered
							//the platform doing the pushing/crushing.
							//The blocker in this case can only be a former passenger.
							if (mo.blockingMobj)
								PushObstacle(mo.blockingMobj, pushForce);
						}
						return false;
					}
				}
			}
		}

		//Anyone left in the 'passengers' array has moved successfully.
		//Adjust their angles and velocities.
		for (int i = 0; i < passengers.Size(); ++i)
		{
			let mo = passengers[i];
			//They'll be linked back into the blockmap in PlatMove()

			if (delta)
				mo.A_SetAngle(Normalize180(mo.angle + delta), SPF_INTERPOLATE);

			if (mo.bOnMobj) //Standing on platform or on another passenger?
				mo.vel.xy = (mo.vel.x*c - mo.vel.y*s, mo.vel.x*s + mo.vel.y*c); //Rotate its velocity

			//Hack: force UpdateWaterLevel() to make a splash if platform movement isn't too slow and going down
			let oldVelZ = mo.vel.z;
			if (mo.vel.z >= -6)
				mo.vel.z = endPos.z - startPos.z;
			mo.UpdateWaterLevel();
			mo.vel.z = oldVelZ;
		}
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
				ForgetPassenger(i--);
				continue;
			}

			//'floorZ' can be the top of a 3D floor that's right below an actor.
			//No 3D floors means 'floorZ' is the current sector's floor height.
			//(In other words 'floorZ' is not another actor's top that's below.)

			//Is 'mo' below our Z? Or is there a 3D floor above our 'top' that's also below 'mo'?
			if (mo.pos.z < pos.z || mo.floorZ > top + TOP_EPSILON ||
				!OverlapXY(self, mo)) //Is out of XY range?
			{
				//Add velocity to the passenger we just lost track of.
				//It's likely to be a player that has jumped away.
				if (args[ARG_OPTIONS] & OPTFLAG_ADDVELJUMP)
					mo.vel += level.Vec3Diff(oldPos, pos);

				ForgetPassenger(i--);
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
	}

	//============================
	// GetUnlinkedPortal
	//============================
	private void GetUnlinkedPortal ()
	{
		if (lastGetUPTime == level.mapTime)
			return; //Already called in this tic
		lastGetUPTime = level.mapTime;

		bool noIterator = (user_portalLookTics <= 0 || //Line portal blockmap searching is disabled?
			(level.mapTime % user_portalLookTics) );

		//Our bounding box
		double size = radius + EXTRA_SIZE; //Pretend we're a bit bigger
		double minX1 = pos.x - size;
		double maxX1 = pos.x + size;
		double minY1 = pos.y - size;
		double maxY1 = pos.y + size;

		BlockLinesIterator it = (lastUPort || noIterator) ? null : BlockLinesIterator.Create(self, size);
		while (lastUPort || (it && it.Next()))
		{
			Line port = lastUPort ? lastUPort : it.curLine;
			Line dest;
			if (!port.IsLinePortal() || !(dest = port.GetPortalDestination()))
			{
				if (lastUPort)
				{
					lastUPort = null;
					if (!noIterator)
						it = BlockLinesIterator.Create(self, size);
				}
				continue;
			}

			//To be a linked/static line portal, the portal groups must be non-zero
			//and they must be different.
			//This check is not a guarantee and I wish there was a
			//IsLinkedLinePortal() function but at the time of typing there isn't one.
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
						if (!noIterator)
							it = BlockLinesIterator.Create(self, size);
					}
					continue; //We don't want linked/static line portals
				}
			}

			//Line bounding box.
			//Reference for order: https://github.com/coelckers/gzdoom/blob/master/src/common/utility/m_bbox.h
			double minX2 = port.bbox[2]; //left
			double maxX2 = port.bbox[3]; //right
			double minY2 = port.bbox[1]; //bottom
			double maxY2 = port.bbox[0]; //top

			if (minX1 >= maxX2 || minX2 >= maxX1 ||
				minY1 >= maxY2 || minY2 >= maxY1)
			{
				if (lastUPort)
				{
					lastUPort = null;
					if (!noIterator)
						it = BlockLinesIterator.Create(self, size);
				}
				continue; //BBoxes not intersecting
			}

			if (IsBehindLine(pos.xy, port))
			{
				if (lastUPort)
				{
					lastUPort = null;
					if (!noIterator)
						it = BlockLinesIterator.Create(self, size);
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
					if (!noIterator)
						it = BlockLinesIterator.Create(self, size);
				}
				continue; //All corners on one side; there's no intersection with line
			}
			lastUPort = port;
			break;
		}
	}

	//============================
	// TranslatePortalVector
	//============================
	static vector3, double TranslatePortalVector (vector3 vec, Line port, bool isPos, bool backward)
	{
		Line dest;
		if (!port || !(dest = port.GetPortalDestination()))
			return vec, 0;

		int portAlignment = isPos ? port.GetPortalAlignment() : 0;

		if (backward)
		{
			//Swap them
			Line oldPort = port;
			port = dest;
			dest = oldPort;

			//If this is a portal, use its alignment. Else still use the other one's.
			if (port.IsLinePortal())
				portAlignment = isPos ? port.GetPortalAlignment() : 0;
		}

		double delta = DeltaAngle(180 +
		VectorAngle(port.delta.x, port.delta.y),
		VectorAngle(dest.delta.x, dest.delta.y));

		if (isPos)
			vec.xy -= port.v1.p;
		if (delta)
			vec.xy = RotateVector(vec.xy, delta);
		if (isPos)
			vec.xy += dest.v2.p;

		switch (portAlignment)
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

		//This is never called by the portal copy
		if (!portTwin.bNoBlockmap)
		for (int i = 0; i < passengers.Size(); ++i)
		{
			//If any of our passengers have passed through a portal,
			//check if they're on the twin's side of that portal.
			//If so, give them to our twin.
			let mo = passengers[i];
			if (!mo || mo.bDestroyed)
			{
				ForgetPassenger(i--);
				continue;
			}

			if (mo.Distance3D(portTwin) < mo.Distance3D(self) &&
				portTwin.passengers.Find(mo) >= portTwin.passengers.Size())
			{
				let plat = FCW_Platform(mo);
				if (plat && plat.group && plat.group.carrier == self)
					plat.group.carrier = portTwin;

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
				portTwin.ForgetPassenger(i--);
				--oldPortTwinSize;
				continue;
			}

			if (mo.Distance3D(self) < mo.Distance3D(portTwin) &&
				passengers.Find(mo) >= passengers.Size())
			{
				let plat = FCW_Platform(mo);
				if (plat && plat.group && plat.group.carrier == portTwin)
					plat.group.carrier = self;

				portTwin.passengers.Delete(i--);
				--oldPortTwinSize;
				passengers.Push(mo);
			}
		}
	}

	//============================
	// UpdateOldInfo
	//============================
	private void UpdateOldInfo ()
	{
		oldPos = pos;
		oldAngle = angle;
		oldPitch = pitch;
		oldRoll = roll;
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
		let mo = blockingMobj;

		if (!moved && mo)
		{
			let moOldZ = mo.pos.z;
			let moNewZ = newPos.z + self.height;

			//If we could carry it, try to set the obstacle on top of us
			//if its 'maxStepHeight' allows it.
			if (moNewZ > moOldZ && moNewZ - moOldZ <= mo.maxStepHeight && IsCarriable(mo))
			{
				PassengerPreMove(mo);
				bool fits = FitsAtPosition(mo, (mo.pos.xy, moNewZ), true);
				if (fits)
				{
					mo.SetZ(moNewZ);

					//Try one more time
					moved = bPortCopy ? FitsAtPosition(self, newPos) : TryMove(newPos.xy, 1);
					if (!moved)
					{
						mo.SetZ(moOldZ);
						fits = false;
						blockingMobj = mo; //Needed for later; TryMove() might have nulled it
					}
					else
					{
						if (mo is "FCW_Platform")
						{
							mo.SetZ(moOldZ);
							FCW_Platform(mo).PlatMove((mo.pos.xy, moNewZ), mo.angle, mo.pitch, mo.roll, MOVE_QUICK);
						}
						else
						{
							mo.CheckPortalTransition(); //Handle sector portals properly
						}
					}
				}
				PassengerPostMove(mo, fits);
			}
		}
		else if (!moved) //Blocked by geometry or another platform?
		{
			if (args[ARG_OPTIONS] & OPTFLAG_IGNOREGEO)
			{
				moved = true;
				if (!bPortCopy)
					SetOrigin(level.Vec3Offset(pos, newPos - pos), true);
			}
		}

		if (moved && bPortCopy)
		{
			SetOrigin(newPos, true);
		}
		else if (!moved)
		{
			SetZ(oldPos.z);
			if (newPos.z < oldPos.z)
			{
				//If an obstacle is below us and we're attempting to go down, try to stand on it
				let mo = blockingMobj;
				double moTop;
				if (mo && (moTop = mo.pos.z + mo.height) < oldPos.z && OverlapXY(self, mo) && FitsAtPosition(self, (oldPos.xy, moTop)))
				{
					bOnMobj = true;
					SetZ(moTop);
					oldPos.z = moTop;
					if (!bPortCopy)
						CheckPortalTransition(); //Handle sector portals properly

					//Self-note: No, we don't call MovePassengers() here.
					//With a straight-forward downward movement it's not needed.
					//It's not an issue if our passengers are floaters
					//or there's no gravity to move them downward.

					//Try to adjust our twin
					if (portTwin && (!portTwin.bNoBlockmap || !portTwin.bPortCopy))
					{
						vector3 twinPos = TranslatePortalVector(oldPos, (bPortCopy ? portTwin.lastUPort : lastUPort), true, bPortCopy);
						if (twinPos != oldPos && portTwin.pos.z != twinPos.z && FitsAtPosition(portTwin, twinPos))
						{
							portTwin.bOnMobj = true;
							portTwin.SetZ(twinPos.z);
							portTwin.oldPos.z = twinPos.z;
							if (!portTwin.bPortCopy)
								portTwin.CheckPortalTransition(); //Handle sector portals properly
						}
					}
				}
			}
			return false;
		}
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

			if (SpecialBTIActor(mo))
				continue; //Already handled

			if (mo == self)
				continue;

			if (!CollisionFlagChecks(self, mo))
				continue;

			if (stuckActors.Find(mo) < stuckActors.Size())
				continue; //Already in the array

			let plat = FCW_Platform(mo);
			if (plat && (plat.bInMove || (plat.portTwin && plat.portTwin.bInMove) ) )
				continue; //This is likely the platform that carries us; ignore it

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
		double top = pos.z + height;

		for (int i = 0; i < stuckActors.Size(); ++i)
		{
			let mo = stuckActors[i];
			if (!mo || mo.bDestroyed || //Thing_Remove()'d?
				!CollisionFlagChecks(self, mo) || //Non-solid?
				!OverlapZ(self, mo) || !OverlapXY(self, mo) || //No overlap?
				!self.CanCollideWith(mo, false) || !mo.CanCollideWith(self, true) ) //No collision?
			{
				stuckActors.Delete(i--);
				continue;
			}

			int index = passengers.Find(mo);
			if (index < passengers.Size())
			{
				//Try to have it on top of us and deliberately ignore if it gets stuck in another actor
				PassengerPreMove(mo);
				bool fits = FitsAtPosition(mo, (mo.pos.xy, top), true);
				if (fits)
				{
					if (mo is "FCW_Platform")
					{
						FCW_Platform(mo).PlatMove((mo.pos.xy, top), mo.angle, mo.pitch, mo.roll, MOVE_QUICK);
					}
					else
					{
						mo.SetZ(top);
						mo.CheckPortalTransition(); //Handle sector portals properly
					}
					stuckActors.Delete(i--);
				}
				PassengerPostMove(mo, fits);

				if (fits)
					continue;
				else
					ForgetPassenger(index); //Stuck actors can't be passengers
			}
			vector3 pushForce = level.Vec3Diff(pos, mo.pos + (0, 0, mo.height * 0.5)).Unit();
			PushObstacle(mo, pushForce);
		}

		if (stuckActors.Size())
			bOnMobj = true;
	}

	//============================
	// PlatMove
	//============================
	private int PlatMove (vector3 newPos, double newAngle, double newPitch, double newRoll, PMoveTypes moveType)
	{
		// "Quick move" is used to correct the position/angles and it is assumed
		// that 'newPos/Angle/Pitch/Roll' is only marginally different from
		// the current position/angles.

		FCW_Platform plat;

		if (moveType != MOVE_QUICK)
		for (int i = -1; i == -1 || (group && i < group.members.Size()); ++i)
		{
			plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			if (moveType == MOVE_NORMAL)
			{
				plat.GetUnlinkedPortal();
				if (plat.lastUPort && !plat.portTwin)
				{
					//Create invisible portal twin to help with non-static line portal collision/physics
					plat.portTwin = FCW_Platform(Spawn(plat.GetClass(), TranslatePortalVector(plat.pos, plat.lastUPort, true, false)));
					plat.portTwin.portTwin = plat;
					plat.portTwin.bPortCopy = true;
					plat.portTwin.bInvisible = true;
				}
			}

			if (plat.portTwin)
			{
				//Take into account SetActorFlag() shenanigans.
				//For sanity's sake just copy some
				//of the flags that are defined in
				//the "default" block plus CANNOTPUSH and PUSHABLE.
				//INTERPOLATEANGLES is a render flag so skip it.

				plat.portTwin.bActLikeBridge = plat.bActLikeBridge;
				plat.portTwin.bNoGravity = plat.bNoGravity;
				plat.portTwin.bCanPass = plat.bCanPass;
				plat.portTwin.bSolid = plat.bSolid;
				plat.portTwin.bShootable = plat.bShootable;
				plat.portTwin.bNoDamage = plat.bNoDamage;
				plat.portTwin.bNoBlood = plat.bNoBlood;
				plat.portTwin.bDontThrust = plat.bDontThrust;
				plat.portTwin.bNotAutoAimed = plat.bNotAutoAimed;
				plat.portTwin.bCannotPush = plat.bCannotPush;
				plat.portTwin.bPushable = plat.bPushable;
				plat.portTwin.args[ARG_OPTIONS] = plat.args[ARG_OPTIONS];
				plat.portTwin.args[ARG_CRUSHDMG] = plat.args[ARG_CRUSHDMG];

				if (plat.portTwin.bNoBlockmap && plat.lastUPort)
				{
					plat.portTwin.A_ChangeLinkFlags(YES_BMAP);
					plat.portTwin.SetOrigin(TranslatePortalVector(plat.pos, plat.lastUPort, true, false), true);
				}
				else if (!plat.portTwin.bNoBlockmap && !plat.lastUPort)
				{
					plat.portTwin.A_ChangeLinkFlags(NO_BMAP); //No collision while not needed (don't destroy it - not here)
				}
			}

			if (!plat.GetNewPassengers(moveType == MOVE_TELEPORT) ||
				(plat.portTwin && !plat.portTwin.bNoBlockmap &&
				!plat.portTwin.GetNewPassengers(moveType == MOVE_TELEPORT) ) )
			{
				return 0; //GetNewPassengers() detected a stuck actor that couldn't be resolved
			}
		}

		if (moveType != MOVE_QUICK)
		for (int i = -1; i == -1 || (group && i < group.members.Size()); ++i)
		{
			plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			//Get all passengers that are platforms and call their GetNewPassengers() now.
			//That should allow them to take some of our other passengers.
			for (int iPass = 0; iPass < plat.passengers.Size(); ++iPass)
			{
				let platPass = FCW_Platform(plat.passengers[iPass]);
				if (!platPass || platPass.bNoBlockmap) //They shouldn't have NOBLOCKMAP now - this is taken care of below
					continue;
				platPass.GetNewPassengers(moveType == MOVE_TELEPORT);

				//If passengers get stolen the array size will shrink
				//and this one's position in the array might have changed.
				//So take that into account.
				iPass = plat.passengers.Find(platPass);
			}

			//Do the same for our portal twin
			if (plat.portTwin && !plat.portTwin.bNoBlockmap)
			for (int iPass = 0; iPass < plat.portTwin.passengers.Size(); ++iPass)
			{
				let platPass = FCW_Platform(plat.portTwin.passengers[iPass]);
				if (!platPass || platPass.bNoBlockmap) //They shouldn't have NOBLOCKMAP now - this is taken care of below
					continue;
				platPass.GetNewPassengers(moveType == MOVE_TELEPORT);

				//If passengers get stolen the array size will shrink
				//and this one's position in the array might have changed.
				//So take that into account.
				iPass = plat.portTwin.passengers.Find(platPass);
			}
		}

		for (int i = -1; i == -1 || (group && i < group.members.Size()); ++i)
		{
			plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			plat.bMoved = false;
			plat.bInMove = true;

			// The goal is to move all passengers as if they were one entity.
			// The only things that should block any of them are
			// non-passengers and geometry.
			// The exception is if a passenger can't fit at its new position
			// in which case it will be "solid" for the others.
			//
			// To accomplish this each of them will temporarily
			// be removed from the blockmap.

			for (int iPass = 0; iPass < plat.passengers.Size(); ++iPass)
			{
				let mo = plat.passengers[iPass];
				if (mo && !mo.bNoBlockmap)
				{
					plat.PassengerPreMove(mo);
					mo.A_ChangeLinkFlags(NO_BMAP);
				}
				else
				{
					plat.ForgetPassenger(iPass--);
				}
			}

			//We have to do the same for our portal twin's passengers
			if (plat.portTwin)
			for (int iPass = 0; iPass < plat.portTwin.passengers.Size(); ++iPass)
			{
				let mo = plat.portTwin.passengers[iPass];
				if (mo && !mo.bNoBlockmap)
				{
					plat.portTwin.PassengerPreMove(mo);
					mo.A_ChangeLinkFlags(NO_BMAP);
				}
				else
				{
					plat.portTwin.ForgetPassenger(iPass--);
				}
			}
		}

		int result = DoMove(newPos, newAngle, newPitch, newRoll, moveType) ? 1 : 0;
		if (result)
			result = MoveGroup(moveType) ? 2 : 1;

		for (int i = -1; i == -1 || (group && i < group.members.Size()); ++i)
		{
			plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			plat.bInMove = false;

			//Handle anyone left in the 'passengers' array
			for (int iPass = 0; iPass < plat.passengers.Size(); ++iPass)
			{
				let mo = plat.passengers[iPass];
				if (mo && mo.bNoBlockmap)
					mo.A_ChangeLinkFlags(YES_BMAP);
				if (mo)
					plat.PassengerPostMove(mo, plat.bMoved);
			}

			if (plat.portTwin)
			for (int iPass = 0; iPass < plat.portTwin.passengers.Size(); ++iPass)
			{
				let mo = plat.portTwin.passengers[iPass];
				if (mo && mo.bNoBlockmap)
					mo.A_ChangeLinkFlags(YES_BMAP);
				if (mo)
					plat.portTwin.PassengerPostMove(mo, plat.bMoved);
			}
		}
		return result;
	}

	//============================
	// DoMove
	//============================
	private bool DoMove (vector3 newPos, double newAngle, double newPitch, double newRoll, PMoveTypes moveType)
	{
		if (pos == newPos && angle == newAngle && pitch == newPitch && roll == newRoll)
			return true;

		double delta, piDelta, roDelta;
		if (moveType == MOVE_QUICK || moveType == MOVE_TELEPORT || pos == newPos)
		{
			UpdateOldInfo();

			angle = newAngle;
			pitch = newPitch;
			roll = newRoll;

			//For MovePassengers()
			delta = DeltaAngle(oldAngle, newAngle);
			piDelta = moveType == MOVE_TELEPORT ? 0 : DeltaAngle(oldPitch, newPitch);
			roDelta = moveType == MOVE_TELEPORT ? 0 : DeltaAngle(oldRoll, newRoll);

			if (lastUPort)
			{
				double angDiff;
				[portTwin.oldPos, angDiff] = TranslatePortalVector(oldPos, lastUPort, true, false);
				portTwin.angle = newAngle + angDiff;

				if (oldPos != newPos)
					portTwin.SetOrigin(TranslatePortalVector(newPos, lastUPort, true, false), true);
				else if (portTwin.oldPos != portTwin.pos)
					portTwin.SetOrigin(portTwin.oldPos, true);
			}
		}

		if (moveType == MOVE_QUICK)
		{
			if (pos != newPos)
			{
				SetOrigin(newPos, true);
				let oldPrev = prev;
				CheckPortalTransition(); //Handle sector portals properly
				prev = oldPrev;
			}

			MovePassengers(oldPos, pos, angle, delta, piDelta, roDelta, false);
			if (lastUPort)
				portTwin.MovePassengers(portTwin.oldPos, portTwin.pos, portTwin.angle, delta, piDelta, roDelta, false);
			ExchangePassengersWithTwin();

			GetStuckActors();
			if (portTwin)
				portTwin.GetStuckActors();
			bMoved = true;
			return true;
		}

		if (moveType == MOVE_TELEPORT || pos == newPos)
		{
			if (pos != newPos)
			{
				SetOrigin(newPos, false);
				CheckPortalTransition(); //Handle sector portals properly
			}

			bool result = true;
			bool movedMine = MovePassengers(oldPos, pos, angle, delta, piDelta, roDelta, moveType == MOVE_TELEPORT);

			if (!movedMine || (lastUPort &&
				!portTwin.MovePassengers(portTwin.oldPos, portTwin.pos, portTwin.angle, delta, piDelta, roDelta, moveType == MOVE_TELEPORT) ) )
			{
				if (movedMine)
					MovePassengers(pos, oldPos, angle, -delta, -piDelta, -roDelta, true); //Move them back

				GoBack();
				if (lastUPort)
					portTwin.GoBack();
				result = false;
			}
			else if (lastUPort)
			{
				ExchangePassengersWithTwin();
			}

			bMoved = result;
			return result;
		}

		int maxSteps = 1;
		vector3 stepMove = level.Vec3Diff(pos, newPos);
		vector3 pushForce = stepMove;

		//If the move is equal or larger than our radius
		//then it has to be split up into smaller steps.
		//This is needed for proper collision.
		//NOTE: This was based on similar code from P_XYMovement().
		double maxMove = max(1, radius - 1);
		double moveSpeed = max(abs(stepMove.x), abs(stepMove.y));
		if (moveSpeed > maxMove)
		{
			maxSteps = int(1 + moveSpeed / maxMove);
			stepMove /= maxSteps;
		}

		for (int step = 0; step < maxSteps; ++step)
		{
			UpdateOldInfo();

			newPos = pos + stepMove;
			if (!PlatTakeOneStep(newPos))
			{
				if (blockingMobj)
				{
					let mo = blockingMobj;
					if (portTwin && !portTwin.bNoBlockmap && lastUPort &&
						mo.Distance3D(portTwin) < mo.Distance3D(self))
					{
						portTwin.PushObstacle(mo, TranslatePortalVector(pushForce, lastUPort, false, false));
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
					portDelta += angDiff; //For SetInterpolationCoordinates()
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
			if (lastUPort)
			{
				vector3 twinPos;
				if (newPos.xy == pos.xy)
				{
					[portTwin.oldPos, angDiff] = TranslatePortalVector(oldPos, lastUPort, true, false);
					portTwin.angle = angle + angDiff;
					twinPos = TranslatePortalVector(pos, lastUPort, true, false);
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
					GoBack();
					if (portTwin.blockingMobj)
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
			if (!movedMine || (lastUPort &&
				!portTwin.MovePassengers(portTwin.oldPos, portTwin.pos, portTwin.angle, delta, piDelta, roDelta, false) ) )
			{
				if (movedMine)
					MovePassengers(pos, myStartPos, angle, -delta, -piDelta, -roDelta, true); //Move them back

				GoBack();
				if (lastUPort)
					portTwin.GoBack();
				return false;
			}

			ExchangePassengersWithTwin();
			CheckPortalTransition(); //Handle sector portals properly
			if (crossedPortal)
			{
				lastUPort = lastUPort.GetPortalDestination();
				lastGetUPTime = -1;
				GetUnlinkedPortal();
			}
		}
		bMoved = true;
		return true;
	}

	//============================
	// Lerp
	//============================
	double Lerp (double p1, double p2)
	{
		return (p1 ~== p2) ? p1 : (p1 + time * (p2 - p1));
	}

	//============================
	// Splerp
	//============================
	double Splerp (double p1, double p2, double p3, double p4)
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

		bool linear = (args[ARG_OPTIONS] & OPTFLAG_LINEAR);
		bool changeAng = ((args[ARG_OPTIONS] | acsFlags) & OPTFLAG_ANGLE);
		bool changePi  = ((args[ARG_OPTIONS] | acsFlags) & OPTFLAG_PITCH);
		bool changeRo  = ((args[ARG_OPTIONS] | acsFlags) & OPTFLAG_ROLL);
		bool faceMove = (args[ARG_OPTIONS] & OPTFLAG_FACEMOVE);

		Vector3 dpos = (0, 0, 0);
		if (faceMove && time > 0)
			dpos = pos;

		vector3 newPos;
		double newAngle = angle;
		double newPitch = pitch;
		double newRoll = roll;

		if (linear)
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

		if (faceMove && changeRo)
			newRoll = 0; //Adjust roll

		if (faceMove && (changeAng || changePi))
		{
			if (linear)
			{
				dpos = pNext - pCurr;
			}
			else if (time > 0) //Spline
			{
				dpos = newPos - dpos;
			}
			else //Spline but with time <= 0
			{
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
			if (changeAng)
				newAngle = VectorAngle(dpos.x, dpos.y);

			//Adjust pitch
			if (changePi)
			{
				double dist = dpos.xy.Length();
				newPitch = dist ? VectorAngle(dist, -dpos.z) : 0;
			}
		}

		if (!faceMove)
		{
			if (linear)
			{
				//Interpolate angle
				if (changeAng)
					newAngle = Lerp(pCurrAngs.x, pNextAngs.x);

				//Interpolate pitch
				if (changePi)
					newPitch = Lerp(pCurrAngs.y, pNextAngs.y);

				//Interpolate roll
				if (changeRo)
					newRoll = Lerp(pCurrAngs.z, pNextAngs.z);
			}
			else //Spline
			{
				//Interpolate angle
				if (changeAng)
					newAngle = Splerp(pPrevAngs.x, pCurrAngs.x, pNextAngs.x, pNextNextAngs.x);

				//Interpolate pitch
				if (changePi)
					newPitch = Splerp(pPrevAngs.y, pCurrAngs.y, pNextAngs.y, pNextNextAngs.y);

				//Interpolate roll
				if (changeRo)
					newRoll = Splerp(pPrevAngs.z, pCurrAngs.z, pNextAngs.z, pNextNextAngs.z);
			}
		}

		//Result == 2 means everyone moved. 1 == this platform moved but not all its groupmates moved.
		//(If this platform isn't in a group then the result is likewise 2 if it moved.)
		int result = PlatMove(newPos, newAngle, newPitch, newRoll, MOVE_NORMAL);
		if (result && pos != newPos) //Crossed a portal?
			AdjustInterpolationCoordinates(newPos, pos, DeltaAngle(newAngle, angle));

		return (result == 2);
	}

	//============================
	// MoveGroup
	//============================
	private bool MoveGroup (int moveType)
	{
		if (!group)
			return true;

		double delta = DeltaAngle(groupAngle, angle);
		double piDelta = DeltaAngle(groupPitch, pitch);
		double roDelta = DeltaAngle(groupRoll, roll);

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
				//from the origin's current position to its 'groupPos'
				//and using that to get a offsetted position from
				//the attached platform's 'groupPos'.
				//So we pretty much always go in the opposite direction
				//using our 'groupPos' as a reference point.
				vector3 offset = level.Vec3Diff(pos, groupPos);
				newPos = level.Vec3Offset(plat.groupPos, offset);

				if (changeAng)
					newAngle = plat.groupAngle - delta;
				if (changePi)
					newPitch = plat.groupPitch - piDelta;
				if (changeRo)
					newRoll = plat.groupRoll - roDelta;
			}
			else //Non-mirror movement. Orbiting happens here.
			{
				vector3 offset = level.Vec3Diff(groupPos, plat.groupPos);
				offset = RotateVector3(offset, delta, piDelta, roDelta, groupAngle, false);
				newPos = level.Vec3Offset(pos, offset);

				if (changeAng)
					newAngle = plat.groupAngle + delta;

				if (changePi || changeRo)
				{
					double diff = DeltaAngle(groupAngle, plat.groupAngle);
					double c = cos(diff), s = sin(diff);
					if (changePi)
						newPitch = plat.groupPitch + piDelta*c - roDelta*s;
					if (changeRo)
						newRoll = plat.groupRoll + piDelta*s + roDelta*c;
				}
			}

			if (!plat.DoMove(newPos, newAngle, newPitch, newRoll, moveType) && moveType != MOVE_QUICK)
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

		//Platform will be the activator of each special
		for (int i = 0; i < specList.Size(); i += 6)
			level.ExecuteSpecial(specList[i], self, null, false, specList[i+1], specList[i+2], specList[i+3], specList[i+4], specList[i+5]);
	}

	//============================
	// Deactivate (override)
	//============================
	override void Deactivate (Actor activator)
	{
		if (!bActive || bPortCopy)
			return;

		vel = (0, 0, 0);

		if (!group || !group.origin)
		{
			if (time <= 1.0) //Not reached destination?
				Stopped(oldPos, pos);

			if (portTwin && portTwin.bNoBlockmap && portTwin.bPortCopy)
				portTwin.Destroy();
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

					if (plat.portTwin && plat.portTwin.bNoBlockmap && plat.portTwin.bPortCopy)
						plat.portTwin.Destroy();
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
			if (bPortCopy)
				return;

			vel = (0, 0, 0);

			if (portTwin)
				portTwin.bActive = false;

			if ((args[ARG_OPTIONS] & OPTFLAG_RESUMEPATH) && time <= 1.0)
			{
				bActive = true;
				if (group)
					group.origin = self;
				MustGetNewPassengers(); //Ignore search tic rate; do a search now
				return;
			}

			currNode = firstNode;
			prevNode = firstPrevNode;

			if (currNode)
			{
				portDelta = 0;
				acsFlags = 0;

				bGoToNode = (args[ARG_OPTIONS] & OPTFLAG_GOTONODE);
				if (!bGoToNode) //Don't call specials if going to 'currNode'
				{
					CallNodeSpecials();
					if (bDestroyed || !currNode || currNode.bDestroyed)
						return; //Abort if we or the node got Thing_Remove()'d
				}
				bActive = true;
				if (group)
					group.origin = self;

				if (!bGoToNode)
				{
					double newAngle = (args[ARG_OPTIONS] & OPTFLAG_ANGLE) ? currNode.angle : angle;
					double newPitch = (args[ARG_OPTIONS] & OPTFLAG_PITCH) ? currNode.pitch : pitch;
					double newRoll = (args[ARG_OPTIONS] & OPTFLAG_ROLL) ? currNode.roll : roll;
					PlatMove(currNode.pos, newAngle, newPitch, newRoll, MOVE_TELEPORT);
				}
				else
				{
					MustGetNewPassengers(); //Ignore search tic rate; do a search now
				}
				SetInterpolationCoordinates();
				SetTimeFraction();
				SetHoldTime();
				time = 0;
				reachedTime = 0;
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
					ForgetPassenger(i--);
				else
					mo.vel += pushForce;
			}
		}

		if (portTwin && !portTwin.bNoBlockmap && portTwin.passengers.Size())
		{
			if (lastUPort)
				pushForce = TranslatePortalVector(pushForce, lastUPort, false, false);

			for (int i = 0; i < portTwin.passengers.Size(); ++i)
			{
				let mo = portTwin.passengers[i];
				if (!mo || mo.bDestroyed)
					portTwin.ForgetPassenger(i--);
				else
					mo.vel += pushForce;
			}
		}
	}

	//============================
	// PlatVelMove
	//============================
	private void PlatVelMove ()
	{
		//Handles velocity based movement (from being pushed around)

		//Apparently slamming into the floor/ceiling doesn't
		//count as a cancelled move so take care of that.
		if ((vel.z < 0 && pos.z <= floorZ) ||
			(vel.z > 0 && pos.z + height >= ceilingZ))
		{
			if (!(args[ARG_OPTIONS] & OPTFLAG_IGNOREGEO))
				vel.z = 0;
		}

		if (vel == (0, 0, 0))
			return; //Nothing to do here

		double startAngle = angle;
		vector3 startPos = pos;
		vector3 newPos = pos + vel;
		int result = PlatMove(newPos, angle, pitch, roll, MOVE_NORMAL);
		if (result != 2)
		{
			//Check if it's a culprit that blocks XY movement
			if (!vel.z || blockingLine || (blockingMobj && !OverlapXY(self, blockingMobj)))
			{
				vel = (0, 0, 0);
			}
			else
			{
				//Try again but without the Z component
				vel.z = 0;
				newPos.z = startPos.z;
				if (vel.xy == (0, 0) || (result = PlatMove(newPos, angle, pitch, roll, MOVE_NORMAL)) != 2)
					vel = (0, 0, 0);
			}
		}

		if (result == 2)
		{
			pPrev += vel;
			pCurr += vel;
			if (pos != newPos) //Crossed a portal?
				AdjustInterpolationCoordinates(newPos, pos, DeltaAngle(startAngle, angle));
		}
		else if (result == 1) //This platform has moved, but one or all of its groupmates hasn't
		{
			PlatMove(startPos, startAngle, pitch, roll, MOVE_TELEPORT); //...So move them back
		}
	}

	//============================
	// Tick (override)
	//============================
	override void Tick ()
	{
		//Portal copies aren't meant to think themselves. Not even advance states.
		//The only thing a copy should do is remove itself if its twin is gone.
		if (bPortCopy)
		{
			if (!portTwin)
				Destroy();
			return;
		}

		if (IsFrozen())
			return;

		//Any of the copy's received velocities are passed on to the non-copy twin
		if (portTwin && portTwin.bPortCopy)
		{
			vector3 pVel = portTwin.vel;
			portTwin.vel = (0, 0, 0);

			if (lastUPort && pVel.xy != (0, 0))
				pVel = TranslatePortalVector(pVel, lastUPort, false, true);

			vel += pVel;
		}

		if (group)
		{
			if (group.members.Find(self) >= group.members.Size())
				group.members.Push(self); //Ensure we're in the group array

			if ((!group.origin || (!group.origin.bActive && group.origin.vel == (0, 0, 0))) && (bActive || vel != (0, 0, 0)))
			{
				group.origin = self;
			}
			else if (group.origin && group.origin != self)
			{
				group.origin.vel += vel; //Any member's received velocity is passed on to the origin
				vel = (0, 0, 0);
			}

			//We need to check if the 'carrier' is actually carrying anyone in this group
			if (group.carrier && !(level.mapTime & 127) && //Do this roughly every 3.6 seconds
				group.GetMember(0) == self)
			{
				let carrier = group.carrier;
				if (!carrier.passengers.Size())
				{
					group.carrier = null;
				}
				else for (int iPlat = 0; iPlat < group.members.Size();)
				{
					let plat = group.GetMember(iPlat);
					if (plat && carrier.passengers.Find(plat) < carrier.passengers.Size())
						break; //It does carry one of us

					if (++iPlat >= group.members.Size())
						group.carrier = null; //It doesn't carry any of us
				}
			}
		}

		double oldFloorZ = floorZ;

		// The group origin, if there is one, thinks for the whole group.
		// That means the order in which they think depends on where
		// they are in the group array and not where they are in the thinker list.
		// (In other words, the others think when the origin thinks/ticks.)
		//
		// The intent behind this is to keep the whole group in sync.
		// For example if the advancing of actor states was left up
		// to the thinker list (like with every other actor)
		// the moving bridge construct in the demo map would play
		// its lift sounds slightly out of sync. (2 actors play the sounds.)

		if (!group || !group.origin)
		{
			bOnMobj = false; //Aside from standing on an actor, this can also be "true" later if hitting a lower obstacle while going down or we have stuck actors
			HandleStuckActors();
			HandleOldPassengers();
			UpdateOldInfo();
			if (portTwin && portTwin.bPortCopy)
			{
				portTwin.bOnMobj = bOnMobj;
				portTwin.HandleStuckActors();
				portTwin.HandleOldPassengers();
				portTwin.UpdateOldInfo();
			}
		}
		else if (group.origin == self)
		{
			for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
			{
				let plat = group.GetMember(iPlat);
				if (plat)
				{
					plat.bOnMobj = false;
					plat.HandleStuckActors();
					plat.HandleOldPassengers();
					plat.UpdateOldInfo();
					if (plat.portTwin && plat.portTwin.bPortCopy)
					{
						plat.portTwin.bOnMobj = plat.bOnMobj;
						plat.portTwin.HandleStuckActors();
						plat.portTwin.HandleOldPassengers();
						plat.portTwin.UpdateOldInfo();
					}
				}
			}
		}

		if (!group || group.origin == self)
			PlatVelMove();

		//Handle path following
		while (bActive && (!group || group.origin == self))
		{
			if (holdTime > 0)
			{
				if (!--holdTime) //Finished waiting?
					MustGetNewPassengers(); //Ignore search tic rate; do a search now
				break;
			}

			if (!Interpolate())
			{
				if (stuckActors.Size() || (portTwin && !portTwin.bNoBlockmap && portTwin.stuckActors.Size()))
					break; //Don't bother

				//Something's blocking us so try to move a little closer
				if (reachedTime < time)
				{
					let oldTime = time;
					time = reachedTime + timeFrac * 0.125;
					if (Interpolate())
						reachedTime = time;
					time = oldTime;
				}
				break;
			}

			reachedTime = time;
			time += timeFrac;
			if (time > 1.0) //Reached destination?
			{
				bool goneToNode = bGoToNode;
				if (bGoToNode)
				{
					bGoToNode = false; //Reached 'currNode'
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

				//Make sure we're exactly at our intended position.
				//(It doesn't matter if we can't fit at this "intended position"
				//because that's what the "stuck actors" logic is there for.)
				bool changeAng = (!(args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) && ((args[ARG_OPTIONS] | acsFlags) & OPTFLAG_ANGLE));
				bool changePi =  (!(args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) && ((args[ARG_OPTIONS] | acsFlags) & OPTFLAG_PITCH));
				bool changeRo =  (!(args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) && ((args[ARG_OPTIONS] | acsFlags) & OPTFLAG_ROLL));
				PlatMove(pNext, changeAng ? pNextAngs.x : angle,
								changePi  ? pNextAngs.y : pitch,
								changeRo  ? pNextAngs.z : roll, MOVE_QUICK);

				if (finishedPath)
				{
					Deactivate(self);
				}
				else
				{
					SetInterpolationCoordinates();
					time -= 1.0;
					reachedTime = time;
					vel = (0, 0, 0);
				}
			}
			break;
		}

		//Handle friction, gravity, and other misc things
		if (!group || !group.origin || group.origin == self)
		{
			CheckFloorCeiling();
			UpdateWaterLevel();

			bool getAverage = (group && group.origin && group.members.Size() > 1);
			bool onGround = (bOnMobj || pos.z <= floorZ);
			bool yesGravity = !bNoGravity;
			bool yesFriction = !bNoFriction;

			if (yesGravity && !onGround)
			{
				Actor mo;
				onGround = bOnMobj = ((lastGetNPTime == level.mapTime && !lastGetNPResult) ||
					((mo = blockingMobj) && mo.pos.z <= pos.z && OverlapXY(self, mo)) ||
					!TestMobjZ(true) );
			}

			if (group && group.origin)
			for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
			{
				let plat = group.GetMember(iPlat);
				if (!plat || plat == self)
					continue;

				plat.CheckFloorCeiling();
				plat.UpdateWaterLevel();

				//Find a member who is gravity bound and/or is "on the ground" and/or doesn't ignore friction
				onGround |= (plat.bOnMobj || plat.pos.z <= plat.floorZ);
				yesGravity |= !plat.bNoGravity;
				yesFriction |= !plat.bNoFriction;

				if (yesGravity && !onGround)
				{
					Actor mo;
					onGround = plat.bOnMobj = ((plat.lastGetNPTime == level.mapTime && !plat.lastGetNPResult) ||
						((mo = plat.blockingMobj) && mo.pos.z <= plat.pos.z && OverlapXY(plat, mo)) ||
						!plat.TestMobjZ(true) );
				}
			}

			if (yesFriction && vel != (0, 0, 0))
			{
				double fric;
				if (!onGround)
				{
					fric = platAirFric;
				}
				else
				{
					let oldNoGrav = bNoGravity;
					bNoGravity = false; //A little hack to make GetFriction() give us a actual friction value
					fric = GetFriction();
					bNoGravity = oldNoGrav;
				}

				if (getAverage)
				{
					//Get the average friction from the group
					int count = 1;
					double sum = fric;

					for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
					{
						let plat = group.GetMember(iPlat);
						if (!plat || plat == self)
							continue;

						++count;
						if (!onGround)
						{
							sum += plat.platAirFric;
						}
						else
						{
							let oldNoGrav = plat.bNoGravity;
							plat.bNoGravity = false; //A little hack to make GetFriction() give us a actual friction value
							sum += plat.GetFriction();
							plat.bNoGravity = oldNoGrav;
						}
					}
					fric = sum / count;
				}

				if (!onGround)
					vel *= fric;
				else
					vel.xy *= fric;

				if (abs(vel.x) < minVel) vel.x = 0;
				if (abs(vel.y) < minVel) vel.y = 0;
				if ((onGround && vel.z < 0) || abs(vel.z) < minVel) vel.z = 0;
			}

			if (yesGravity && !onGround)
			{
				let oldNoGrav = bNoGravity;
				bNoGravity = false;
				double grav = GetGravity();
				bNoGravity = oldNoGrav;

				if (getAverage)
				{
					//Get the average gravity from the group
					int count = 1;
					double sum = grav;

					for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
					{
						let plat = group.GetMember(iPlat);
						if (!plat || plat == self)
							continue;

						++count;
						oldNoGrav = plat.bNoGravity;
						plat.bNoGravity = false;
						sum += plat.GetGravity();
						plat.bNoGravity = oldNoGrav;
					}
					grav = sum / count;
				}
				FallAndSink(grav, oldFloorZ);
			}
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
	// CheckFloorCeiling
	//============================
	private void CheckFloorCeiling ()
	{
		if (args[ARG_OPTIONS] & OPTFLAG_IGNOREGEO)
			return;

		if (PlatIsActive() && !PlatHasMoved(true)) //Possibly blocked?
			FindFloorCeiling(); //If there's a 3D floor, sets 'floorZ' and 'ceilingZ' accordingly.

		let oldZ = pos.z;

		if (pos.z < floorZ || ceilingZ - floorZ < height)
			SetZ(floorZ);
		else if (pos.z + height > ceilingZ)
			SetZ(ceilingZ - height);

		pPrev.z += pos.z - oldZ;
		pCurr.z += pos.z - oldZ;
	}

	//============================
	// FallAndSink (override)
	//============================
	override void FallAndSink (double grav, double oldFloorZ)
	{
		//This is a modified version of the original function
		if (!grav)
			return;

		double startVelZ = vel.z;
		int wLevel = waterLevel;
		int m = mass;

		if (group && group.origin && group.members.Size() > 1)
		{
			//Get the average water level and average mass from the group
			int count = 1;
			int sums[2] = {wLevel, m};

			for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
			{
				let plat = group.GetMember(iPlat);
				if (!plat || plat == self)
					continue;

				++count;
				sums[0] += plat.waterLevel;
				sums[1] += plat.mass;
			}
			wLevel = sums[0] / count;
			m = sums[1] / count;
		}

		if (wLevel == 0)
		{
			// [RH] Double gravity only if running off a ledge. Coming down from
			// an upward thrust (e.g. a jump) should not double it.
			if (vel.z == 0 && oldFloorZ > floorZ && pos.z == oldFloorZ)
				vel.z -= grav + grav;
			else
				vel.z -= grav;
		}
		else if (wLevel >= 1)
		{
			double sinkSpeed = -0.5; // -WATER_SINK_SPEED;

			// Scale sinkSpeed by mass (m), with
			// 100 being equivalent to a player.
			sinkSpeed = sinkSpeed * clamp(m, 1, 4000) / 100;

			if (vel.z < sinkSpeed)
			{ // Dropping too fast, so slow down toward sinkSpeed.
				vel.z -= max(sinkSpeed * 2, -8.0);
				if (vel.z > sinkSpeed)
					vel.z = sinkSpeed;
			}
			else if (vel.z > sinkSpeed)
			{ // Dropping too slow/going up, so trend toward sinkSpeed.
				vel.z = startVelZ + max(sinkSpeed / 3, -8.0);
				if (vel.z < sinkSpeed)
					vel.z = sinkSpeed;
			}
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

		return (plat.bActive || plat.vel != (0, 0, 0));
	}

	//============================
	// PlatHasMoved
	//============================
	bool PlatHasMoved (bool posOnly = false)
	{
		//When checking group members we only care about the origin.
		//Either "every member has moved" or "every member has not moved."
		let plat = self;
		if (group && group.origin)
			plat = group.origin;

		return ((plat.bActive || plat.vel != (0, 0, 0)) && (
				plat.pos != plat.oldPos ||
				(!posOnly && plat.angle != plat.oldAngle) ||
				(!posOnly && plat.pitch != plat.oldPitch) ||
				(!posOnly && plat.roll != plat.oldRoll) ) );
	}

	//============================
	// CommonACSSetup
	//============================
	private void CommonACSSetup (int travelTime)
	{
		currNode = null; //Deactivate when done moving
		prevNode = null;
		time = 0;
		reachedTime = 0;
		holdTime = 0;
		timeFrac = 1.0 / max(1, travelTime); //Time unit is always in tics from the ACS side
		bActive = true;
		if (group)
			group.origin = self;
		portDelta = 0;
		acsFlags = (OPTFLAG_ANGLE | OPTFLAG_PITCH | OPTFLAG_ROLL);
		pPrev = pCurr = pos;
		pPrevAngs = pCurrAngs = (
			Normalize180(angle),
			Normalize180(pitch),
			Normalize180(roll));
		vel = (0, 0, 0);
		MustGetNewPassengers(); //Ignore search tic rate; do a search now
	}

	//
	//
	// Everything below this point are
	// ACS centric utility functions.
	//
	//

	//============================
	// Move (ACS utility)
	//============================
	static void Move (Actor act, int platTid, double x, double y, double z, bool exactPos, int travelTime, double ang = 0, double pi = 0, double ro = 0, bool exactAngs = false)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		for (let plat = FCW_Platform(it ? it.Next() : act); plat; plat = it ? FCW_Platform(it.Next()) : null)
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
	static void MoveToSpot (Actor act, int platTid, int spotTid, int travelTime, bool dontRotate = false)
	{
		//This is the only place you can make a platform use any actor as a travel destination
		ActorIterator it = spotTid ? level.CreateActorIterator(spotTid) : null;
		Actor spot = it ? it.Next() : act;
		if (!spot)
			return; //No spot? Nothing to do

		it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		for (let plat = FCW_Platform(it ? it.Next() : act); plat; plat = it ? FCW_Platform(it.Next()) : null)
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
	// IsActive (ACS utility)
	//============================
	static bool IsActive (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		for (let plat = FCW_Platform(it ? it.Next() : act); plat; plat = it ? FCW_Platform(it.Next()) : null)
		{
			if (plat.PlatIsActive())
				return true;
		}
		return false;
	}

	//============================
	// HasMoved (ACS utility)
	//============================
	static bool HasMoved (Actor act, int platTid, bool posOnly = false)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		for (let plat = FCW_Platform(it ? it.Next() : act); plat; plat = it ? FCW_Platform(it.Next()) : null)
		{
			if (plat.PlatHasMoved(posOnly))
				return true;
		}
		return false;
	}

	//============================
	// SetNodePath (ACS utility)
	//============================
	static void SetNodePath (Actor act, int platTid, int nodeTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		for (let plat = FCW_Platform(it ? it.Next() : act); plat; plat = it ? FCW_Platform(it.Next()) : null)
			plat.SetUpPath(nodeTid, false);
	}

	//============================
	// SetOptions (ACS utility)
	//============================
	static void SetOptions (Actor act, int platTid, int toSet, int toClear = 0)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		for (let plat = FCW_Platform(it ? it.Next() : act); plat; plat = it ? FCW_Platform(it.Next()) : null)
		{
			// NOTE: Changing most options on an active platform has an immediate effect except for
			// 'OPTFLAG_GOTONODE' which is checked in Activate() meaning you can't stop it from
			// going to the first node once it's started. (Not like this anyway).
			//
			// And changing 'OPTFLAG_STARTACTIVE' after it has called PostBeginPlay() is utterly pointless.

			int oldFlags = plat.args[ARG_OPTIONS];
			int newFlags = (oldFlags & ~toClear) | toSet;
			plat.args[ARG_OPTIONS] = newFlags;

			//If for some reason you wanted to cancel ACS induced rotations, you can do it this way
			plat.acsFlags &= ~(toClear & (OPTFLAG_ANGLE | OPTFLAG_PITCH | OPTFLAG_ROLL));

			//If the "mirror" option has changed and the group has an "origin", we must
			//update the group info. (Having an "origin" usually means they are moving.)
			if (((oldFlags ^ newFlags) & OPTFLAG_MIRROR) && plat.group && plat.group.origin && plat != plat.group.origin)
				plat.UpdateGroupInfo();
		}
	}

	//============================
	// GetOptions (ACS utility)
	//============================
	static int GetOptions (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		let plat = FCW_Platform(it ? it.Next() : act);
		return plat ? plat.args[ARG_OPTIONS] : 0;
	}

	//============================
	// SetCrushDamage (ACS utility)
	//============================
	static void SetCrushDamage (Actor act, int platTid, int damage)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		for (let plat = FCW_Platform(it ? it.Next() : act); plat; plat = it ? FCW_Platform(it.Next()) : null)
			plat.args[ARG_CRUSHDMG] = damage;
	}

	//============================
	// GetCrushDamage (ACS utility)
	//============================
	static int GetCrushDamage (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		let plat = FCW_Platform(it ? it.Next() : act);
		return plat ? plat.args[ARG_CRUSHDMG] : 0;
	}

	//============================
	// MakeGroup (ACS utility)
	//============================
	static void MakeGroup (Actor act, int platTid, int otherPlatTid)
	{
		if (platTid && !otherPlatTid)
		{
			//Swap them. (If zero, 'otherPlatTid' is activator.)
			int firstPlatTid = platTid;
			platTid = otherPlatTid;
			otherPlatTid = firstPlatTid;
		}

		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		for (let plat = FCW_Platform(it ? it.Next() : act); plat; plat = it ? FCW_Platform(it.Next()) : null)
			plat.SetUpGroup(otherPlatTid, true);
	}

	//============================
	// LeaveGroup (ACS utility)
	//============================
	static void LeaveGroup (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		for (let plat = FCW_Platform(it ? it.Next() : act); plat; plat = it ? FCW_Platform(it.Next()) : null)
		{
			if (!plat.group)
				continue;

			int index = plat.group.members.Find(plat);
			if (index < plat.group.members.Size())
				plat.group.members.Delete(index);

			if (plat.group.origin == plat)
				plat.group.origin = null;

			plat.group = null;
		}
	}

	//============================
	// DisbandGroup (ACS utility)
	//============================
	static void DisbandGroup (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		for (let plat = FCW_Platform(it ? it.Next() : act); plat; plat = it ? FCW_Platform(it.Next()) : null)
		{
			if (!plat.group)
				continue;

			for (int i = 0; i < plat.group.members.Size(); ++i)
			{
				let member = plat.group.GetMember(i);
				if (member && member != plat)
					member.group = null;
			}
			plat.group = null;
		}
	}

	//============================
	// SetAirFriction (ACS utility)
	//============================
	static void SetAirFriction (Actor act, int platTid, double fric)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		for (let plat = FCW_Platform(it ? it.Next() : act); plat; plat = it ? FCW_Platform(it.Next()) : null)
			plat.platAirFric = fric;
	}

	//============================
	// GetAirFriction (ACS utility)
	//============================
	static double GetAirFriction (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FCW_Platform") : null;
		let plat = FCW_Platform(it ? it.Next() : act);
		return plat ? plat.platAirFric : 0;
	}
} //End of FCW_Platform class definition

/******************************************************************************

 The following concerns old classes that make use of the old
 InterpolationPoint class. They should not use FCW_PlatformNode
 since it wasn't made for them.

******************************************************************************/

struct FCW_OldStuff_Common play
{
	static void CheckNodeTypes (Actor pointer)
	{
		InterpolationPoint node;
		Array<InterpolationPoint> foundNodes; //To avoid infinite loops

		if (pointer is "PathFollower")
			node = InterpolationPoint(pointer.lastEnemy ? pointer.lastEnemy : pointer.target);
		else
			node = InterpolationPoint(pointer).next;

		//Go through the detected nodes. If any of them are the new type
		//then bluntly and forcefully inform the mapper that's a no-no.
		while (node)
		{
			if (foundNodes.Find(node) < foundNodes.Size())
				return;
			foundNodes.Push(node);

			if (node is "FCW_PlatformNode")
			{
				String cls = pointer.GetClassName();
				cls.Replace("FCW_OldStuff_", "");
				Console.Printf("\ck'" .. cls .. "' with tid " .. pointer.tid .. " at position " .. pointer.pos ..
							":\nis pointing at a 'Platform Interpolation Point' with tid ".. node.tid .. " at position " .. node.pos .. "\n.");
				new("FCW_OldStuff_DelayedAbort");
			}

			pointer = node;
			node = node.next;
		}
	}
}

mixin class FCW_OldStuff
{
	override void PostBeginPlay ()
	{
		Super.PostBeginPlay();
		FCW_OldStuff_Common.CheckNodeTypes(self);
	}
}

class FCW_OldStuff_PathFollower : PathFollower replaces PathFollower { mixin FCW_OldStuff; }
class FCW_OldStuff_MovingCamera : MovingCamera replaces MovingCamera { mixin FCW_OldStuff; }
class FCW_OldStuff_ActorMover : ActorMover replaces ActorMover { mixin FCW_OldStuff; }

class FCW_OldStuff_DelayedAbort : Thinker
{
	int startTime;

	override void PostBeginPlay ()
	{
		startTime = level.mapTime;
	}

	override void Tick ()
	{
		if (level.mapTime - startTime >= TICRATE)
			ThrowAbortException("Path followers, moving cameras, and actor movers are not meant to use 'Platform Interpolation Points'. Please use the old 'Interpolation Point' instead. \n\nLikewise, the old 'Interpolation Point' should not point to a 'Platform Interpolation Point' nor vice-versa.\n.");
	}
}
