class FishyPlatformGeneric : FishyPlatform
{
	Default
	{
		//$Title Generic Platform (set model and size in the 'Custom' tab)
		Radius 16; //A visual size for UDB's Visual Mode since it has a default model
		Height 16;
	}

	States
	{
	Spawn:
		MODL A -1; //In order to use A_ChangeModel() it needs to have a modeldef entry with a sprite other than TNT1A0
		Stop;
	}

	//===User variables that are parameters for A_SetSize() and A_ChangeModel()===//
	//$UserDefaultValue -1
	double user_set_radius;
	//$UserDefaultValue -1
	double user_set_height;

	string user_cm_modeldef;
	int user_cm_modelindex;
	string user_cm_modelpath;
	string user_cm_model;
	int user_cm_skinindex;
	string user_cm_skinpath;
	string user_cm_skin;
	int user_cm_flags;
	//$UserDefaultValue -1
	int user_cm_generatorindex;
	int user_cm_animationindex;
	string user_cm_animationpath;
	string user_cm_animation;

	override void BeginPlay () //This gets called before any user vars are set - any atypical default values have to be set here
	{
		Super.BeginPlay();
		user_set_radius = -1; //Passing a negative value to A_SetSize() means "don't change"
		user_set_height = -1;
		user_cm_generatorindex = -1;
	}

	override void PostBeginPlay ()
	{
		if (!bPortCopy) //Make sure this isn't a invisible portal copy
		{
			A_ChangeModel(
				user_cm_modeldef,
				user_cm_modelindex,
				user_cm_modelpath,
				user_cm_model,
				user_cm_skinindex,
				user_cm_skinpath,
				user_cm_skin,
				user_cm_flags,
				user_cm_generatorindex,
				user_cm_animationindex,
				user_cm_animationpath,
				user_cm_animation
			);

			A_SetSize(user_set_radius, user_set_height);
		}
		Super.PostBeginPlay();
	}
}
