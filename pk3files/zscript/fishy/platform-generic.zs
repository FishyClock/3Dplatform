class FishyPlatformGeneric : FishyPlatform
{
	Default
	{
		//$Title Generic Platform (set model and size in the 'Custom' tab)
	}

	States
	{
	Spawn:
		MODL A -1;
		Stop;
	}

	//===User variables that are parameters for A_SetSize() and A_ChangeModel()===//
	double user_radius;
	double user_height;

	string user_cmp1_modeldef;
	int user_cmp2_modelindex;
	string user_cmp3_modelpath;
	string user_cmp4_model;
	int user_cmp5_skinindex;
	string user_cmp6_skinpath;
	string user_cmp7_skin;
	int user_cmp8_flags;
	//$UserDefaultValue -1
	int user_cmp9_generatorindex;
	int user_cmp10_animationindex;
	string user_cmp11_animationpath;
	string user_cmp12_animation;

	override void BeginPlay () //This gets called before any user vars are set - any atypical default values have to be set here
	{
		Super.BeginPlay();
		user_cmp9_generatorindex = -1;
	}

	override void PostBeginPlay ()
	{
		if (!bPortCopy) //Make sure this isn't a invisible portal copy
		{
			A_ChangeModel(
				user_cmp1_modeldef,
				user_cmp2_modelindex,
				user_cmp3_modelpath,
				user_cmp4_model,
				user_cmp5_skinindex,
				user_cmp6_skinpath,
				user_cmp7_skin,
				user_cmp8_flags,
				user_cmp9_generatorindex,
				user_cmp10_animationindex,
				user_cmp11_animationpath,
				user_cmp12_animation
			);

			A_SetSize(user_radius, user_height);
		}
		Super.PostBeginPlay();
	}
}
