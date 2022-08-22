//$GZDB_SKIP

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
				Console.Printf("\ck'" .. cls .. "' with tid " .. pointer.tid .. " at " .. pointer.pos ..
							":\nis pointing at a 'Platform Interpolation Point' with tid ".. node.tid .. " at " .. node.pos .. "\n.");
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
			ThrowAbortException("Path followers, moving cameras, and actor movers are not meant to use 'Platform Interpolation Points'. Please use the old 'Interpolation Point' instead. \n\nLikewise, the old 'Interpolation Point' should not point to a 'Platform Interpolation Point'.\n.");
	}
}
