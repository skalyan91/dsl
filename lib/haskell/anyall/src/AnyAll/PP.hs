{-# LANGUAGE OverloadedStrings #-}

module AnyAll.PP (ppQTree, hardnormal, softnormal, cStyle, haskellStyle) where

import AnyAll.BoolStruct
import AnyAll.Relevance
import AnyAll.Types hiding ((<>))
import Control.Monad (forM_)
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.Aeson.Types
import Data.ByteString.Lazy qualified as B
import Data.ByteString.Lazy.UTF8 (toString)
import Data.HashMap.Strict as Map
import Data.List
import Data.Maybe
import Data.String (IsString)
import Data.Text qualified as T
import Data.Tree
import Prettyprinter
import Prettyprinter.Render.Util.SimpleDocTree
import Text.Pretty.Simple (pPrint)

data Style ann = Style
                 { s_parens :: Doc ann -> Doc ann
                 , s_not :: String
                 , s_and :: String
                 , s_or  :: String
                 }

cStyle, haskellStyle, pythonStyle :: (Pretty txt) => OptionallyLabeledBoolStruct txt -> Doc ann

-- | render an BoolStruct to a C-style syntax
cStyle       = mystyle (Style parens "!"   "&&"  "||")

-- | render an BoolStruct to Haskell-style syntax
haskellStyle = mystyle (Style parens "not" "&&"  "||")

-- | render an BoolStruct to Python-style syntax
pythonStyle  = mystyle (Style parens "not" "and" "or")

mystyle :: (Pretty txt) => Style ann -> OptionallyLabeledBoolStruct txt -> Doc ann
mystyle _ (Leaf x)     = pretty x
mystyle s (All lbl xs) = parens (hsep (intersperse (pretty $ s_and s) (mystyle s <$> xs)))
mystyle s (Any lbl xs) = parens (hsep (intersperse (pretty $ s_or  s) (mystyle s <$> xs)))
mystyle s (Not     x ) = pretty (s_not s) <+> mystyle s x

ppline = Prettyprinter.line

svwrap View = angles
svwrap Hide = parens
svwrap Ask  = brackets

markbox (Default (Right (Just True ))) sv = svwrap sv "YES"
markbox (Default (Right (Just False))) sv = svwrap sv " NO"
markbox (Default (Right  Nothing    )) sv = svwrap sv "  ?"
markbox (Default (Left  (Just True ))) sv = svwrap sv "yes"
markbox (Default (Left  (Just False))) sv = svwrap sv " no"
markbox (Default (Left   Nothing    )) sv = svwrap sv "   "
                                                                 
hardnormal, softnormal :: Marking T.Text -> OptionallyLabeledBoolStruct T.Text -> QTree T.Text
hardnormal m = relevant Hard m Nothing

softnormal m = relevant Soft m Nothing

docQ1 :: (IsString a, Ord a, Show a, Pretty a) => Marking a -> Tree (Q a) -> Doc ann
docQ1 m (Node (Q sv  Neg              pp              v) c) = markbox v sv <+>              ": !" <+> nest 2 (hsep $ docQ1 m <$> c)
docQ1 m (Node (Q sv (Simply a)        pp              v) _) = markbox v sv <+> pretty a
docQ1 m (Node (Q sv  And       (Just (Pre     p1   )) v) c) = markbox v sv <+> pretty p1 <> ":" <> nest 2 (ppline <> vsep ((\i -> "&" <+> docQ1 m i) <$> c))
docQ1 m (Node (Q sv  And       (Just (PrePost p1 p2)) v) c) = markbox v sv <+> pretty p1 <> ":" <> nest 2 (ppline <> vsep ((\i -> "&" <+> docQ1 m i) <$> c)) <> ppline <> pretty p2
docQ1 m (Node (Q sv  And       Nothing                v) c) = markbox v sv <+> "all of:"        <> nest 2 (ppline <> vsep ((\i -> "&" <+> docQ1 m i) <$> c))
docQ1 m (Node (Q sv  Or        Nothing                v) c) = markbox v sv <+> "any of:"        <> nest 2 (ppline <> vsep ((\i -> "|" <+> docQ1 m i) <$> c))
docQ1 m (Node (Q sv  Or        (Just (Pre     p1   )) v) c) = markbox v sv <+> pretty p1 <> ":" <> nest 2 (ppline <> vsep ((\i -> "|" <+> docQ1 m i) <$> c))
docQ1 m (Node (Q sv  Or        (Just (PrePost p1 p2)) v) c) = markbox v sv <+> pretty p1 <> ":" <> nest 2 (ppline <> vsep ((\i -> "|" <+> docQ1 m i) <$> c)) <> ppline <> pretty p2

ppQTree :: OptionallyLabeledBoolStruct T.Text -> Map.HashMap T.Text (Either (Maybe Bool) (Maybe Bool)) -> IO ()
ppQTree i mm = do
  let m = Marking (Default <$> mm)
      hardresult = hardnormal m i
      softresult = softnormal m i
  print $ "*"  <+> "Marking:" <+> (pretty $ Prelude.drop 9 $ show m) <> ppline
  print $ "**" <+> "soft result =" <+> markbox (mark (rootLabel softresult)) View
  print $ "**" <+> "hard result =" <+> markbox (mark (rootLabel hardresult)) View
  print $ nest 3 $ "   =" <+> docQ1 m hardresult <> ppline

  print $ "**" <+> "JSON:"
  B.putStr $ asJSON hardresult
  print ppline

  print $ "**" <+> "For UI:"
  B.putStr $ getForUI hardresult
  print ppline
  
  print $ "**" <+> "C-style:"
  print (cStyle i)
  print ppline

  print $ "**" <+> "show of the BoolStruct:"
  pPrint i
  print ppline

  print $ "**" <+> "JSON of the BoolStruct:"
  putStrLn $ toString $ encodePretty i
  print ppline

  print $ "**" <+> "show of the (DefaultLabeled) BoolStruct:"
  pPrint $ alwaysLabeled i
  print ppline

  print $ "**" <+> "JSON of the (DefaultLabeled) BoolStruct:"
  putStrLn $ toString $ encodePretty $ alwaysLabeled i
  print ppline


instance (IsString t, Pretty t, Pretty a) => Pretty (BoolStruct (Maybe (Label t)) a) where
  pretty (Leaf a)            = pretty a
  pretty (All Nothing    xs)             = pretty (All (Just (Pre "All of the following:")) xs)
  pretty (All (Just (Pre     p1   )) xs) = nest 4 (vsep $ pretty p1 : (pretty <$> xs)) 
  pretty (All (Just (PrePost p1 p2)) xs) = nest 4 (vsep $ pretty p1 : (pretty <$> xs)) <> line <> pretty p2
  pretty (Any Nothing    xs)             = pretty (Any (Just (Pre "Any of the following:")) xs)
  pretty (Any (Just (Pre     p1   )) xs) = nest 4 (vsep $ pretty p1 : (pretty <$> xs)) 
  pretty (Any (Just (PrePost p1 p2)) xs) = nest 4 (vsep $ pretty p1 : (pretty <$> xs)) <> line <> pretty p2
  pretty (Not            x ) = "not" <+> pretty x

instance (Pretty a) => Pretty (Label a) where
  pretty (Pre     p1)    = pretty p1
  pretty (PrePost p1 p2) = pretty p1 <+> "..." <+> pretty p2
