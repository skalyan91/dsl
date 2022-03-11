

abstract UDExt = UDApp ** {

  cat
    UDFragment ;
    [UDFragment]{2};

  fun

    -- Compositional,
    -- Add a UDS as an adverbial
    Cond : UDS -> UDFragment -> UDFragment ; -- the king must sing if the prime minister is happy
    Temporal : Adv -> UDFragment -> UDFragment ; -- the king must sing after noon
    Given : UDS -> UDFragment -> UDFragment ; -- the king must sing given that the prime minister is happy
    Upon : (becoming_aware : UDS) ->
           (king_may_sing : UDFragment) ->
           UDFragment ; -- Upon becoming aware, the king may sing

    -- Standalone sentence of each field
    CondStandalone,
      TemporalStandalone,
      GivenStandalone,
      UponStandalone : UDS -> UDFragment ;

    -- Templates
    CondTemporal : (cond : UDS) -> (temp : Adv) -> (king_must_sing : UDFragment) -> UDFragment ; -- if the prime minister is happy, [the king must sing] by noon.

    -- the king must sing by noon, if the following conditions hold:
    -- * PM is happy
    -- * queen had a nice breakfast

    CondUpon : (cond, upon : UDS) -> (king_must_sing: UDFragment) -> UDFragment ;
    -- if the prime minister is happy, upon opening the door, [the king must sing] .

    CondGiven : (cond, given : UDS) -> (king_must_sing: UDFragment) -> UDFragment ;
    -- [the king must sing], if the following conditions hold:
      -- * the prime minister is happy, the door is open.

    -- CondGivenTemporal : (cond, given, temp : UDS) -> (king_must_sing : UDFragment) -> UDFragment ;

    -- CondTemporalUpon : (cond, temp, upon : UDS) -> (king_must_sing : UDFragment)  -> UDFragment ;
    -- -- if the prime minister is happy, [the king must sing] after lunch upon opening the door

    -- CondGivenUpon : (cond, given, upon : UDS) -> (king_must_sing : UDFragment)  -> UDFragment ;
    -- -- if the prime minister is happy, and the queen had a nice breakfast, [the king must sing] upon opening the door

    -- GF funs that correspond to LS.Types constructors
    -- Deontic
    DMust, DMay, DShant : UDS -> UDS ;

    -- MyToken
    Every,
    TokAll,
    Party : NP -> NP ;

    -- RPRel
    RPis,
    RPeq,
    RPlt,
    RPlte,
    RPgt,
    RPgte,
    RPelem,
    RPnotElem : NP -> UDS -> UDFragment ; -- TODO: types?

    Means : NP -> UDS -> UDFragment ; -- foo MEANS bar -- what types to use??? "eyes IS (left IS blue AND right IS brown)"
    HornClause2 : (breach_is_severe : UDFragment) -> (data_is_lost : UDS) -> UDFragment ; -- breach is severe WHEN data is lost

    Who : UDS -> NP -> NP ; -- EVERY king WHO is a singer
    subjAction : NP -> UDS -> UDFragment ;

  -- AnyAll library in GF
    CN_AP_Conj_CNs_of_NP : AP -> Conj -> [CN] -> NP -> CN ; -- unauthorised access or copying of personal data

  -- Aarne
    Adv_no_later_than_Num_calendar_days_after_the_day_UDS : Numeral -> UDS -> UDFragment ;

}

{-
In NLG.hs:

subjA' <- parseSubj (subj rl) -- "qualifying person"

We can already assume that this is a noun phrase kind of thing
(despite that we parsed it into UDS)

We pattern match the constructors root_only and rootN_
and whatever is the argument of rootN_, is an actual NP

root_only (rootN_ (MassNP (AdjCN (PresPartAP (UseV qualify_V))) (UseN person_N)))

-}
