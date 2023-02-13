{-# OPTIONS_GHC -Wno-name-shadowing #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GADTs, NamedFieldPuns, FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}

module LS.NLP.NLG where


import LS.NLP.NL4
import LS.NLP.NL4Transformations
import LS.Types
import LS.Rule (Rule(..))      
import PGF
import Data.Maybe (catMaybes)
import qualified Data.Text as Text
import qualified AnyAll as AA
import System.Environment (lookupEnv)
import Paths_natural4
import Data.Foldable as F

data NLGEnv = NLGEnv
  { gfGrammar :: PGF
  , gfLang :: Language
  , gfParse :: Type -> Text.Text -> [Expr]
  , gfLin :: Expr -> Text.Text
  , verbose :: Bool
  }

myNLGEnv :: IO NLGEnv
myNLGEnv = do
  mpn <- lookupEnv "MP_NLG"
  let verbose = maybe False (read :: String -> Bool) mpn
  grammarFile <- getDataFileName $ gfPath "NL4.pgf"
  gr <- readPGF grammarFile
  let lang = case readLanguage "NL4Eng" of 
        Nothing -> error $ "concrete language NL4Eng not found among " <> show (languages gr)
        Just l -> l
      myParse typ txt = parse gr lang typ (Text.unpack txt)
      myLin = Text.pack . linearize gr lang
  pure $ NLGEnv gr lang myParse myLin verbose

gfPath :: String -> String
gfPath x = "grammars/" ++ x

-----------------------------------------------------------------------------
-- Main

-- WIP: crude way of keeping track of whether we're in hence, lest or whatever
data RecursionLevel = TopLevel | MyHence Int | MyLest Int 
  deriving (Eq,Ord,Show)

getLevel :: RecursionLevel -> Int
getLevel l = case l of
  TopLevel -> 2
  MyHence i -> i
  MyLest i -> i 

debugNesting :: RecursionLevel -> (Text.Text, Text.Text)
debugNesting TopLevel = (Text.pack "", Text.pack "")
debugNesting (MyLest _) = (Text.pack "If you disobey, then", Text.pack "D:")
debugNesting (MyHence _) = (Text.pack "When that happens,", Text.pack "\\:D/")

nlg :: NLGEnv -> Rule -> IO Text.Text
nlg = nlg' TopLevel

nlg' :: RecursionLevel -> NLGEnv -> Rule -> IO Text.Text
nlg' thl env rule = case rule of 
    Regulative {subj,who,deontic,action,lest,hence} -> do
      let subjExpr = parseSubj env subj
          deonticExpr = parseDeontic deontic
          actionExpr = parseAction env action
          whoSubjExpr = case who of 
                        Just w -> GSubjWho subjExpr (bsWho2gfWho (parseWhoBS env w))
                        Nothing -> subjExpr
          ruleText = gfLin env $ gf $ GRegulative whoSubjExpr deonticExpr actionExpr
          ruleTextDebug = Text.unwords [prefix, ruleText, suffix]
      lestText <- case lest of 
                    Just r -> do 
                      rt <- nlg' (MyLest i) env r
                      pure $ pad rt
                    Nothing -> pure mempty
      henceText <- case hence of 
                    Just r -> do 
                      rt <- nlg' (MyHence i) env r
                      pure $ pad rt
                    Nothing -> pure mempty

--      pure $ Text.unlines [ruleText, henceText, lestText]
      pure $ Text.strip $ Text.unlines [ruleTextDebug, henceText, lestText]
    Hornlike {clauses} -> do
      let headLins = gfLin env . gf . parseConstraint env . hHead <$> clauses -- :: [GConstraint] -- this will not become a question
          parseBodyHC cl = case hBody cl of 
            Just bs -> gfLin env $ gf $ bsConstraint2gfConstraint $ parseConstraintBS env bs
            Nothing -> mempty
          bodyLins = parseBodyHC <$> clauses
      pure $ Text.unlines $ headLins <> ["when"] <> bodyLins
    RuleAlias mt -> do
      let ruleText = gfLin env $ gf $ parseSubj env $ mkLeafPT $ mt2text mt
          ruleTextDebug = Text.unwords [prefix, ruleText, suffix]
      pure $ Text.strip ruleTextDebug
    DefNameAlias {} -> pure mempty
    _ -> pure $ "NLG.hs is under construction, we don't support yet " <> Text.pack (show rule)
  where
    (prefix,suffix) = debugNesting thl
    i = getLevel thl + 2
    pad x = Text.replicate i " " <> x


-- | rewrite statements into questions, for use by the Q&A web UI
--
-- +-----------------+-----------------------------------------------------+
-- | input           | the data breach, occurs on or after 1 Feb 2022      |
-- | output          | Did the data breach occur on or after 1 Feb 2022?   |
-- +-----------------+-----------------------------------------------------+
-- | input           | Organisation, NOT, is a Public Agency               |
-- | intermediate    | (AA.Not (...) :: BoolStructT                        |
-- | output          | Is the Organisation a Public Agency?                |
-- +-----------------+-----------------------------------------------------+
-- | input           | Claim Count <= 2                                    |
-- | intermediate    | RPConstraint (RPMT ["Claim Count"]) RelLTE          |
-- |                 |               (RPMT ["2"]) :: RelationalPredicate   |
-- | output          | Have there been more than two claims?               |
-- +-----------------+-----------------------------------------------------+


ruleQuestions :: NLGEnv -> Maybe (MultiTerm,MultiTerm) -> Rule -> IO [AA.OptionallyLabeledBoolStruct Text.Text]
ruleQuestions env alias rule = do
  let (youExpr, orgExpr) =
        case alias of
          Just (you,org) -> 
              case parseSubj env . mkLeafPT . mt2text <$> [you, org] of
                [y,o] -> (y,o) -- both are parsed
                _ -> (GYou, GYou) -- dummy values
          Nothing -> (GYou, GYou) -- dummy values
  case rule of
    Regulative {subj,who,cond,upon} -> do
      let subjExpr = parseSubj env subj
          aliasExpr = if subjExpr==orgExpr then youExpr else subjExpr
          mkWhoQ = gfLin env . gf . GqWHO aliasExpr . parseWho env -- :: RelationalPredicate -> Text
          mkCondQ = gfLin env . gf . GqCOND . parseCond env
          mkUponQ = gfLin env . gf . GqUPON aliasExpr . parseUpon env -- :: ParamText -> Text
          qWhoBS = fmap (mkWhoQ <$>) who -- fmap is for Maybe, <$> for BoolStruct
          qCondBS = fmap (mkCondQ <$>) cond
          qUponBS = case upon of 
                      Just u -> Just $ AA.Leaf $ mkUponQ u
                      Nothing -> Nothing
      pure $ catMaybes [qWhoBS, qCondBS, qUponBS]
    Hornlike {clauses} -> do
      let getBodyBS cl = case hBody cl of 
                          Just bs -> mapTxt $ bsConstraint2questions $ parseConstraintBS env bs
                          Nothing -> AA.Leaf mempty
          bodyBS = getBodyBS <$> clauses
      pure bodyBS
    -- Constitutive {cond} -> do
    --   condBSR <- mapM (bsr2questions qsCond gr dummySubj) cond
    --   pure $ concat $ catMaybes [condBSR]
    DefNameAlias {} -> pure [] -- no questions needed to produce from DefNameAlias
    _ -> pure [AA.Leaf $ Text.pack ("ruleQuestions: doesn't work yet for " <> show rule)]
  where 
    mapTxt :: BoolStructConstraint -> AA.BoolStruct (Maybe (AA.Label Text.Text)) Text.Text
    mapTxt = mapBSLabel (gfLin env . gf) (gfLin env . gf)

nlgQuestion :: NLGEnv -> Rule -> IO [Text.Text]
nlgQuestion env rl = do
  questionsInABoolStruct <- ruleQuestions env Nothing rl -- TODO: the Nothing means there is no AKA
  pure $ concatMap F.toList questionsInABoolStruct

-----------------------------------------------------------------------------
-- Parsing fields into GF categories – all typed, no PGF.Expr allowed

-- Special constructions for the fields that are BoolStructR
parseConstraintBS :: NLGEnv -> BoolStructR -> BoolStructConstraint
parseConstraintBS env = mapBSLabel (parsePre env) (parseConstraint env)

parseWhoBS :: NLGEnv -> BoolStructR -> BoolStructWho
parseWhoBS env = mapBSLabel (parsePre env) (parseWho env)

parseCondBS :: NLGEnv -> BoolStructR -> BoolStructCond
parseCondBS env = mapBSLabel (parsePre env) (parseCond env)

-- not really parsing, just converting nL4 constructors to GF constructors
parseDeontic :: Deontic -> GDeontic
parseDeontic DMust = GMUST
parseDeontic DMay = GMAY
parseDeontic DShant = GSHANT

-- TODO: stop using *2text, instead use the internal structure
  -- "respond" :| []  -> respond : VP 
  -- "demand" :| [ "an explanation for your inaction" ] -> demand : V2, NP complement, call ComplV2
  -- "assess" :| [ "if it is a Notifiable Data Breach" ] -> assess : VS, S complement, call ComplS2
parseAction :: NLGEnv -> BoolStructP -> GAction
parseAction env bsp = let txt = bsp2text bsp in
  case parseAny "Action" env txt of 
    [] -> error $ msg "Action" txt
    x:_ -> fg x

parseSubj :: NLGEnv -> BoolStructP -> GSubj
parseSubj env bsp = let txt = bsp2text bsp in
  case parseAny "Subj" env txt of 
    [] -> error $ msg "Subj" txt
    x:_ -> fg x

parseWho :: NLGEnv -> RelationalPredicate -> GWho
parseWho env rp = let txt = rp2text rp in
  case parseAny "Who" env txt of
    [] -> error $ msg "Who" txt
    x:_ -> fg x

parseCond :: NLGEnv -> RelationalPredicate -> GCond
parseCond env rp = let txt = rp2text rp in
  case parseAny "Cond" env txt of
    [] -> error $ msg "Cond" txt
    x:_ -> fg x
                    
parseUpon :: NLGEnv -> ParamText -> GUpon
parseUpon env pt = let txt = pt2text pt in
  case parseAny "Upon" env txt of
    [] -> error $ msg "Upon" txt
    x:_ -> fg x

parseConstraint :: NLGEnv -> RelationalPredicate -> GConstraint
parseConstraint env rp = let txt = rp2text rp in
  case parseAny "Constraint" env txt of
    [] -> error $ msg "Constraint" txt
    x:_ -> fg x

parsePre :: NLGEnv -> Text.Text -> GPre
parsePre env txt = 
  case parseAny "Pre" env txt of
    [] -> GrecoverUnparsedPre $ GString $ Text.unpack txt
    x:_ -> fg x

-- TODO: later if grammar is ambiguous, should we rank trees here?
parseAny :: String -> NLGEnv -> Text.Text -> [Expr] 
parseAny cat env = gfParse env typ 
  where
    typ = case readType cat of 
            Nothing -> error $ unwords ["category", cat, "not found among", show $ categories (gfGrammar env)]
            Just t -> t

msg :: String -> Text.Text -> String 
msg typ txt = "parse" <> typ <> ": failed to parse " <> Text.unpack txt

-----------------------------------------------------------------------------