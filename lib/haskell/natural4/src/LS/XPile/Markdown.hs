{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module LS.XPile.Markdown where

import LS
import LS.NLP.NLG
import AnyAll as AA
import qualified Data.Map as Map
import qualified Data.Text as Text
-- import Debug.Trace (trace)

markdown :: NLGEnv -> [Rule] -> IO String
markdown env rl = do
  nlg <- mapM (nlg env) rl
  return $ concatMap Text.unpack nlg
