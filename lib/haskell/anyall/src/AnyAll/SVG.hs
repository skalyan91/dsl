{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances #-}

module AnyAll.SVG where

import AnyAll.Types

import Graphics.Svg
import qualified Data.Text as T

type Height = Double

(<<-*) :: Show a => AttrTag -> a -> Attribute
(<<-*) tag a = bindAttr tag (T.pack (show a))

makeSvg :: (Height, Element) -> Element
makeSvg (height, geom) =
     doctype
  <> with (svg11_ geom) [Version_ <<- "1.1", Height_ <<-* height]

box :: Double -> Double -> Double -> Double -> Element
box x y w h =
  rect_ [ X_ <<-* x, Y_ <<-* y, Width_ <<-* w, Height_ <<-* h
        , Fill_ <<- "none", Stroke_ <<- "black" ]

line :: (Double , Double) -> (Double, Double) -> Element
line (x1, y1) (x2, y2) =
  line_ [ X1_ <<-* x1, X2_ <<-* x2, Y1_ <<-* y1, Y2_ <<-* y2
        , Stroke_ <<- "grey" ]

item :: Double -> Double -> String -> Element
item x y desc =
  let w = 20
  in
    g_ [] (  box x y w w
          <> text_ [ X_ <<-* (x + w + 5), Y_ <<-* (y + w - 5) ] (toElement desc)  )

move :: (Double, Double) -> Element -> Element
move (x, y) geoms =
  with geoms [Transform_ <<- translate x y]

renderChain :: [(Height, Element)] -> Element
renderChain [] = mempty
renderChain [(_,g)] = g
renderChain ((h,g):hgs) =
  g_ [] (  g
        <> line (10, 20) (10, h)
        <> move (0, h) (renderChain hgs)  )

renderLeaf :: String -> (Height, Element)
renderLeaf desc =
  let height = 25
      geom = item 0 0 desc
  in (height, geom)

renderSuffix :: Double -> Double -> String -> (Height, Element)
renderSuffix x y desc =
  let h = 20 -- h/w of imaginary box
      geom :: Element
      geom = g_ [] ( text_ [ X_ <<-* x, Y_ <<-* (y + h - 5) ] (toElement desc) )
  in (h, geom)

renderAll :: Label -> [Item] -> (Height, Element)
renderAll (Pre prefix) childnodes =
  let
      hg = map renderItem childnodes
      (hs, gs) = unzip hg

      height = sum hs + 30

      geom :: Element
      geom = g_ [] (  item 0 0 prefix
                   -- elbow connector
                   <> line (10, 20) (10, 25)
                   <> line (10, 25) (40, 25)
                   <> line (40, 25) (40, 30)
                   -- children translated by (30, 30)
                   <> move (30, 30) (renderChain hg)  )
  in (height, geom)
renderAll (PrePost prefix suffix) childnodes =
  let hg = map renderItem childnodes
      (hs, gs) = unzip hg

      (fh, fg) = renderSuffix 0 0 suffix

      height = sum hs + fh + 30

      geom :: Element
      geom = g_ [] (  item 0 0 prefix
                   <> line (10, 20) (10, 25)
                   <> line (10, 25) (40, 25)
                   <> line (40, 25) (40, 30)
                   <> move (30, 30) (renderChain hg)
                   <> move (40, 30 + sum hs) fg  )
  in (height, geom)

renderAny :: Label -> [Item] -> (Height, Element)
renderAny (Pre prefix) childnodes =
  let hg = map renderItem childnodes
      (hs, gs) = unzip hg

      height = sum hs + 25

      geom :: Element
      geom = g_ [] (  item 0 0 prefix
                   <> line (10, 20) (10, sum (init hs) + 25 + 10)
                   <> move (30, 25) (go 0 hg)  )
                 where go y [] = mempty
                       go y ((h,g):hgs) =
                         g_ [] (  g
                               <> line (-20, 10) (0, 10)
                               <> move (0, h) (go (y+h) hgs)  )
  in (height, geom)
renderAny (PrePost prefix suffix) childnodes =
  let hg = map renderItem childnodes
      (hs, gs) = unzip hg

      (fh, fg) = renderSuffix 0 0 suffix

      height = sum hs + fh + 25

      geom :: Element
      geom = g_ [] (  item 0 0 prefix
                   <> line (10, 20) (10, sum (init hs) + 25 + 10)
                   <> move (30, 25) (go 0 hg)
                   <> move (40, 25 + sum hs) fg)
                 where go y [] = mempty
                       go y ((h,g):hgs) =
                         g_ [] (  g
                               <> line (-20, 10) (0, 10)
                               <> move (0, h) (go (y+h) hgs)  )
  in (height, geom)


renderItem :: Item -> (Height, Element)
renderItem (Leaf label) = renderLeaf label
renderItem (All label args) = renderAll label args
renderItem (Any label args) = renderAny label args

toy :: (Height, Element)
toy = renderItem $
  All ( PrePost "You need all of" "to survive." )
      [ Leaf "Item 1;"
      , Leaf "Item 2;"
      , Any ( Pre "Item 3 which may be satisfied by any of:" )
            [ Leaf "3.a;"
            , Leaf "3.b; or"
            , Leaf "3.c;" ]
      , Leaf "Item 4; and"
      , All ( Pre "Item 5 which requires all of:" )
            [ Leaf "5.a;"
            , Leaf "5.b; and"
            , Leaf "5.c." ] ]