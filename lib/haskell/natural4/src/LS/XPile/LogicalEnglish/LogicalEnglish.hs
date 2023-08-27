{-# OPTIONS_GHC -W #-}

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedRecordDot, DuplicateRecordFields #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}

{-# LANGUAGE DataKinds, KindSignatures, AllowAmbiguousTypes #-}
{-# LANGUAGE PatternSynonyms, ViewPatterns #-}
{-|

We're trying to work with the rules / AST instead, 
in part because we don't need most of the stuff Interpreter.hs provides,
and in part to avoid breaking if the spec / API for Interpreter.hs changes.
After all, the design intentions for this short-term LE transpiler aren't the same as those for the analzyer (which is part of what will hopefully become an effort in longer-term, more principled language development).
-}

module LS.XPile.LogicalEnglish.LogicalEnglish (toLE)  where

import Text.Pretty.Simple   ( pShowNoColor )
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

import Prettyprinter
  ( Doc,
    Pretty (pretty))
import LS.PrettyPrinter
    ( myrender, vvsep, (</>), (<//>) )
import Prettyprinter.Interpolate (__di)
    

import qualified AnyAll as AA
import LS.Types qualified as L4
import LS.Types (RelationalPredicate(..), RPRel(..), MTExpr, BoolStructR(..), BoolStructT)
import LS.Rule qualified as L4 (Rule(..))
import LS.XPile.LogicalEnglish.Types
import LS.XPile.LogicalEnglish.ValidateL4Input
      (L4Rules, ValidHornls, Unvalidated,
      check, refine, loadRawL4AsUnvalid)
import LS.XPile.LogicalEnglish.SimplifyL4 (simplifyL4ruleish) -- TODO: Add import list
import LS.XPile.LogicalEnglish.IdVars (idVarsInHC)
import LS.XPile.LogicalEnglish.GenNLAs (nlasFromVarsHC)
import LS.XPile.LogicalEnglish.GenLEHCs (leHCFromLabsHC)
import LS.XPile.LogicalEnglish.Pretty()

import LS.XPile.LogicalEnglish.UtilsLEReplDev -- for prototyping

{- 

TODO: After we get a v simple end-to-end prototype out, 
we'll add functionality for checking the L4 input rules __upfront__ for things like whether it's using unsupported keywords, whether the input is well-formed by the lights of the translation rules, and so forth. 
(This should be done with Monad.Validate or Data.Validation -- XPileLog isn't as good a fit for this.)
The thought is that if the upfront checks fail, we'll be able to exit gracefully and provide more helpful diagnostics / error messages. 

But for now, we will help ourselves, undeservedly, to the assumption that the L4 input is wellformed. 


TODO: Add property based tests
  EG: 
    * If you add a new var anywhere in a randomly generated LamAbs HC, the new LE HC should have an 'a' in front of that var
    * If you take a rand generated LamAbs HC with a var v and add another occurrence of `v` before the old one, the ordering of variables with an `a` prefix in the corresponding new LE HC should differ from that in the old LE HC in the appropriate way (this should be made a bit more precise depending on what is easy to implement)
    * Take a randomly generated LamABs HC with vars that potentially have multiple occurrences and generate the LE HC from it. For every var in the HC, the 'a' prefix should only appear once.
    * There should be as many NLAs as leaves in the HC (modulo lib NLAs)

-}


{-------------------------------------------------------------------------------
   L4 rules -> SimpleL4HCs -> LamAbsRules
-------------------------------------------------------------------------------}

-- | TODO: Work on implementing this and adding the Monad Validate or Data.Validation stuff instead of Maybe (i.e., rly doing checks upfront and carrying along the error messages and potential warnings) after getting enoguh of the main transpiler out
checkAndRefine :: L4Rules Unvalidated -> Maybe (L4Rules ValidHornls)
checkAndRefine rawrules = do
  validatedL4rules <- check rawrules
  return $ refine validatedL4rules


{-------------------------------------------------------------------------------
   Orchestrating and pretty printing
-------------------------------------------------------------------------------}

-- | Generate LE Nat Lang Annotations from VarsHCs  
allNLAs :: [VarsHC] -> HS.HashSet LENatLangAnnot
allNLAs vhcs = HS.unions $ map nlasFromVarsHC vhcs

doc2str :: Doc ann -> String
doc2str = T.unpack . myrender 

toLE :: [L4.Rule] -> String
toLE l4rules = 
  let vhcs = map (idVarsInHC . simplifyL4ruleish) l4rules
      nlas    = HS.toList (allNLAs vhcs) -- TODO: sort the nlas
      lehcs   = map leHCFromLabsHC vhcs
      leProg = MkLEProg { nlas = nlas, leHCs = lehcs }
  in doc2str . pretty $ leProg
    
{-
note
------

Key types from codebase:
  type ParamText = NonEmpty TypedMulti
  type TypedMulti = (NonEmpty MTExpr, Maybe TypeSig)

  data MTExpr = MTT Text.Text -- ^ Text string
              | MTI Integer   -- ^ Integer
              | MTF Float     -- ^ Float
              | MTB Bool      -- ^ Boolean
            deriving (Eq, Ord, Show, Generic, ToJSON)

    -- | the parser returns a list of MTExpr, to be parsed further at some later point
  type MultiTerm = [MTExpr] --- | apple | banana | 100 | $100 | 1 Feb 1970

  given    :: Maybe ParamText
  aka the stuff in the given field is a non-mt list of (NonEmpty MTExpr, Maybe TypeSig)

-}