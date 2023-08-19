{-# OPTIONS_GHC -W #-}

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedRecordDot, DuplicateRecordFields #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DataKinds, KindSignatures, AllowAmbiguousTypes #-}
{-# LANGUAGE PatternSynonyms, ViewPatterns #-}


module LS.XPile.LogicalEnglish.SimplifyL4 where
-- TODO: Make export list

import Data.Text qualified as T
import Data.Bifunctor       ( first )
import Data.HashMap.Strict qualified as HM
import Data.HashSet qualified as HS
import Data.Hashable (Hashable)
import GHC.Generics (Generic)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.HashMap.Strict qualified as Map
import Control.Monad.Identity ( Identity )
import Data.String (IsString)
import Data.List.NonEmpty qualified as NE
import Debug.Trace (trace)

import qualified AnyAll as AA
import LS.Types qualified as L4
import LS.Types (RelationalPredicate(..), RPRel(..), MTExpr(..), BoolStructR(..), BoolStructT)
import LS.Rule qualified as L4 (Rule(..))
import LS.XPile.LogicalEnglish.Types
import LS.XPile.LogicalEnglish.ValidateL4Input
      (L4Rules, ValidHornls, Unvalidated,
      loadRawL4AsUnvalid)

import LS.XPile.LogicalEnglish.UtilsLEReplDev -- for prototyping

{-
TODO: All the `error ..`s should be checked for upfront in the ValidateL4Input module
-}


-- TODO: Switch over to this, e.g. with coerce or with `over` from new-type generic when have time: simplifyL4rule :: L4Rules ValidHornls -> SimpleL4HC
{- | 
  Precondition: assume that the input L4 rules only have 1 HC in their Horn clauses. 
  TODO: This invariant will have to be established in the next iteration of work on this transpiler (mainly by desugaring the 'ditto'/decision table stuff accordingly first) 
-}
simplifyL4rule :: L4.Rule -> SimpleL4HC
simplifyL4rule l4r =
  let gvars = gvarsFromL4Rule l4r
      (rhead, rbody) = simplifyL4HC (Prelude.head $ L4.clauses l4r)
                      -- this use of head will be safe in the future iteration when we do validation and make sure that there will be exactly one HC in every L4 rule that this fn gets called on
  in MkSL4hc { givenVars = gvars, head = rhead, body = rbody }



{-------------------------------------------------------------------------------
    Simplifying L4 HCs
-------------------------------------------------------------------------------}

-- TODO: Look into how to make it clear in the type signature that the head is just an atomic propn
simplifyL4HC :: L4.HornClause2 -> (Propn [Cell], Maybe (Propn [Cell]))
simplifyL4HC l4hc = (simplifyHead l4hc.hHead, fmap simplifyHcBodyBsr l4hc.hBody)
-- ^ There are HCs with Nothing in the body in the encoding 

simplifyHead :: L4.RelationalPredicate -> Propn [Cell]
simplifyHead = \case
  (RPMT exprs)                      -> Atomic $ mtes2cells exprs
  (RPConstraint exprsl RPis exprsr) -> simpbodRPC @RPis exprsl exprsr
                                    {- ^ 
                                      1. Match on RPis directly cos no other rel operator shld appear here in the head: 
                                        the only ops tt can appear here from the parse are RPis or RPlt or RPgt,
                                        but the encoding convention does not allow for  RPlt or RPgt in the head.

                                      2. Can't just lowercase IS and transform the mtexprs to (either Text or Integer) Cells 
                                        because it could be a IS-number, 
                                        and when making template vars later, we need to be able to disambiguate between something tt was an IS-kw and smtg tt was originally lowercase 'is'. 
                                        TODO: But do think more abt this when we implement the intermed stage
                                        TODO: Need to account for / stash info for IS NOT --- I think that would be handled in the intermed stage, but shld check again when we get there.

                                      We handle the case of RPis in a RPConstraint the same way in both the body and head. 
                                    -}

  (RPBoolStructR _ _ _)             -> error "should not be seeing RPBoolStructR in head"
  (RPParamText _)                   -> error "should not be seeing RPParamText in head"
  (RPnary _rel _rps)                -> error "I don't see any RPnary in the head in Joe's encoding, so."


{- ^
An example of an is-num pattern in a RPConstraint
[ HC
    { hHead = RPConstraint
        [ MTT "total savings" ] RPis
        [ MTI 100 ]
    , hBody = Just
        ( All Nothing
            [ Leaf
                ( RPConstraint
                    [ MTT "initial savings" ] RPis
                    [ MTF 22.5 ]
                )
-}

{-
data RPRel = RPis | RPhas | RPeq | RPlt | RPlte | RPgt | RPgte | RPelem | RPnotElem | RPnot | RPand | RPor | RPsum | RPproduct | RPsubjectTo | RPmap
-}

{-
inspiration:

from types.hs
rp2mt :: RelationalPredicate -> MultiTerm
rp2mt (RPParamText    pt)            = pt2multiterm pt
rp2mt (RPMT           mt)            = mt
rp2mt (RPConstraint   mt1 rel mt2)   = mt1 ++ [MTT $ rel2txt rel] ++ mt2
rp2mt (RPBoolStructR  mt1 rel bsr)   = mt1 ++ [MTT $ rel2txt rel] ++ [MTT $ bsr2text bsr] -- [TODO] is there some better way to bsr2mtexpr?
rp2mt (RPnary         rel rps)       = MTT (rel2txt rel) : concatMap rp2mt rps

----------
data BoolStruct lbl a =
    Leaf                       a
  | All lbl [BoolStruct lbl a] -- and
  | Any lbl [BoolStruct lbl a] --  or
  | Not             (BoolStruct lbl a)
  deriving (Eq, Ord, Show, Generic, Functor, Foldable, Traversable)
instance (Hashable lbl, Hashable a) => Hashable (BoolStruct lbl a)

type OptionallyLabeledBoolStruct a = BoolStruct (Maybe (Label T.Text)) a
type BoolStructR = AA.OptionallyLabeledBoolStruct RelationalPredicate

----
data RelationalPredicate = RPParamText   ParamText                     -- cloudless blue sky
                         | RPMT MultiTerm  -- intended to replace RPParamText. consider TypedMulti?
                         | RPConstraint  MultiTerm RPRel MultiTerm     -- eyes IS blue
                         | RPBoolStructR MultiTerm RPRel BoolStructR   -- eyes IS (left IS blue AND right IS brown)
                         | RPnary RPRel [RelationalPredicate] 
                                -- RPnary RPnot [RPnary RPis [MTT ["the sky"], MTT ["blue"]
----
data Propn a =
    Atomic a
    -- ^ the structure in 'IS MAX / MIN / SUM / PROD t_1, ..., t_n' would be flattened out so that it's just a list of Cells --- i.e., a list of strings 
    | IsOpSuchThat OpWhere a
    -- ^ IS MAX / MIN / SUM / PROD where φ(x) -- these require special indentation, and right now our LE dialect only accepts an atomic propn as the arg to such an operator
    | And [Propn a]
    | Or  [Propn a]
    | Not [Propn a]
    deriving (Eq, Ord, Show, Generic, Functor, Foldable, Traversable)
-}

{-------------------------------------------------------------------------------
    simplifying body of L4 HC
-------------------------------------------------------------------------------}

simplifyHcBodyBsr :: L4.BoolStructR -> Propn [Cell]
simplifyHcBodyBsr = \case
  AA.Leaf rp      -> simplifybodyRP rp 
  AA.All _ propns -> And (map simplifyHcBodyBsr propns)
  AA.Any _ propns -> Or (map simplifyHcBodyBsr propns)
  AA.Not propn    -> Not (simplifyHcBodyBsr propn)
{- ^ where a 'L4 propn' = BoolStructR =  BoolStruct _lbl RelationalPredicate.
Note that a BoolStructR is NOT a 'RPBoolStructR' --- a RPBoolStructR is one of the data constructors for the RelationalPredicate sum type
-}

simplifybodyRP :: RelationalPredicate -> Propn [Cell]
simplifybodyRP = \case
  RPMT exprs                     -> Atomic $ mtes2cells exprs
                                    -- ^ this is the same for both the body and head
  RPConstraint exprsl rel exprsr -> case rel of
                                        RPis -> simpbodRPC @RPis exprsl exprsr
                                        RPor -> simpbodRPC @RPor exprsl exprsr
                                        RPand -> simpbodRPC @RPand exprsl exprsr
                                        {- ^ Special case to handle for RPConstraint in the body but not the head: non-propositional connectives!
                                            EG: ( Leaf
                                                  ( RPConstraint
                                                      [ MTT "data breach" , MTT "came about from"] 
                                                      RPor
                                                      [ MTT "luck, fate", MTT "acts of god or any similar event"]
                                                  )
                                                )                           -}
                                      
  RPBoolStructR exprs rel bsr    -> if rel == RPis 
                                    then simpbodRPBSR exprs bsr
                                    else error "The spec does not support any other RPRel in a RPBoolStructR"
  RPnary rel rps                  -> undefined
  RPParamText _                   -> error "should not be seeing RPParamText in body"


simpbodRPBSR :: [MTExpr] -> BoolStructR -> Propn [Cell]
simpbodRPBSR exprs = \case
  AA.Not (AA.Leaf (RPMT nonPropnalCmplmt)) -> let leftexprs = mtes2cells exprs  
                                              in Atomic $ leftexprs <> [MkCellDiffFr] <> mtes2cells nonPropnalCmplmt
  _                                        -> error "should not be seeing anything other than a Not in the BSR position of a RPBoolStructR"
  -- i wonder if we can avoid having missing-case warnings with a pattern synonym + the complete pragma

{- | 
The main thing that simpbodRPBSR does is rewrite L4's
                    t1 IS NOT t2 
                to 
                  t1 is different from t2

EG of a L4 IS NOT:
```
      ( RPBoolStructR
          [ MTT "stumbling" ] RPis
          ( Not
              ( Leaf
                  ( RPMT
                      [ MTT "walking" ]
                  )
              )
          )
```
-}

--------- simplifying RPConstraint in body of L4 HC ------------------------------------

-- https://www.tweag.io/blog/2022-11-15-unrolling-with-typeclasses/
class SimpBodyRPConstrntRPrel (rp :: RPRel) where
  simpbodRPC :: [MTExpr] -> [MTExpr] -> Propn [Cell]

instance SimpBodyRPConstrntRPrel RPis where
  simpbodRPC exprsl exprsr = Atomic (mtes2cells exprsl <> [MkCellIs] <> mtes2cells exprsr)

instance SimpBodyRPConstrntRPrel RPor where
  simpbodRPC exprsl exprsr = undefined
  -- TODO: implement this!

instance SimpBodyRPConstrntRPrel RPand where
  simpbodRPC exprsl exprsr = undefined
  -- TODO: implement this!


--------------------------------------------------------------------------------



{-------------------------------------------------------------------------------
    Misc
-------------------------------------------------------------------------------}

------------    Extracting vars from given   -----------------------------------

extractGiven :: L4.Rule -> [MTExpr]
  -- [(NE.NonEmpty MTExpr, Maybe TypeSig)]
extractGiven L4.Hornlike {given=Nothing}        = [] 
-- won't need to worry abt this when we add checking upfront
extractGiven L4.Hornlike {given=Just paramtext} = concatMap (NE.toList . fst) (NE.toList paramtext)
extractGiven _                                  = trace "not a Hornlike rule, not extracting given" mempty
-- also won't need to worry abt this when we add checking + filtering upfront


gvarsFromL4Rule :: L4.Rule -> GVarSet
gvarsFromL4Rule rule = let givenMTExprs = extractGiven rule
                       in HS.fromList $ map gmtexpr2gvar givenMTExprs
        where 
          -- | Transforms a MTExpr tt appears in the GIVEN of a HC to a Gvar. This is importantly different from `mtexpr2text` in that it only converts the cases we use for LE and that we would encounter in the Givens on our LE conventions
          gmtexpr2gvar :: MTExpr -> GVar
          gmtexpr2gvar = \case 
            MTT var -> MkGVar var
            _       -> error "non-text mtexpr variable names in the GIVEN are not allowed on our LE spec :)"

------------    MTExprs to [Cell]    ------------------------------------------

mtexpr2cell :: L4.MTExpr -> Cell 
mtexpr2cell = \case 
  MTT t -> MkCellT t
  MTI i -> MkCellNum (MkInteger i)
  MTF f -> MkCellNum (MkFloat f)
  _     -> error "Booleans in cells currently not supported"

-- | convenience function for when `map mtexpr2cell` too wordy 
mtes2cells :: [L4.MTExpr] -> [Cell]
mtes2cells = map mtexpr2cell

--- misc notes
-- wrapper :: L4Rules ValidHornls -> [(NE.NonEmpty MTExpr, Maybe TypeSig)]
-- wrapper = concat . map extractGiven . coerce
