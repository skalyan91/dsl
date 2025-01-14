{-# LANGUAGE DerivingStrategies #-}

{-| transpiler to SVG visualization of the AnyAll and/or trees.

Largely a wrapper. Most of the functionality is in the `AnyAll` lib.

-}

module LS.XPile.SVG where

import AnyAll as AA
import Data.HashMap.Strict qualified as Map
import Data.Text qualified as T
import LS

-- import Debug.Trace (trace)

-- | extract the tree-structured rules from Interpreter
-- for each rule, print as svg according to options we were given

asAAsvg :: AAVConfig -> Interpreted -> [Rule] -> Map.HashMap RuleName (SVGElement, SVGElement, BoolStructT, QTree T.Text)
asAAsvg aavc l4i _rs =
  Map.fromList [ ( concat names
                 , (svgtiny, svgfull, bs, qtree) )
               | (names, bs) <- qaHornsT l4i
               , isInteresting bs
               , let qtree   = softnormal (getMarkings l4i) bs
                     svgtiny = makeSvg $ q2svg' aavc { cscale = Tiny } qtree
                     svgfull = makeSvg $ q2svg' aavc { cscale = Full } qtree
               ]
  where
    -- | don't show SVG diagrams if they only have a single element
    isInteresting :: BoolStruct lbl a -> Bool
    isInteresting (AA.Leaf _) = False
    isInteresting (AA.Not (AA.Leaf _)) = False
    isInteresting _ = True
