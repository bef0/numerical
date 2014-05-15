\begin{code}



{-# LANGUAGE PolyKinds   #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-#  LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-#  LANGUAGE GADTs #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE CPP #-}

module Numerical.Array.Layout.Dense(
  DenseLayout(..)
  ,Locality(..)
  ,Format(..)
  ,Row
  ,Column
  ,Direct
  ,Address(..)
  ,UniformAddressInterval(..) ) where



import Numerical.Nat
import Control.Applicative
import Numerical.Array.Address
import Numerical.Array.Locality
import Numerical.Array.Layout.Base
import Numerical.Array.Shape as S

--import Data.Traversable (Traversable)

import Control.NumericalMonad.State.Strict

import qualified Data.Foldable as F

import Prelude hiding (foldr,foldl,map,scanl,scanr,scanl1,scanr1)



--class Layout form rank => SparseLayout  form  (rank :: Nat) | form -> rank  where



--  lookupIndex :: form -> Index rank -> Maybe Address


  --note that unlike the Layout method  basicToAddress,





--class Layout form rank => DenseLayout  form  (rank :: Nat) | form -> rank  where
  {-
  empty class instances for all the dense Layouts
  -}


class DenseLayout form  (rank :: Nat) | form -> rank  where




    basicToAddress :: form  -> Shape rank Int ->   Address


    basicToIndex :: form -> Address -> Shape rank Int

    --unchecked
    --nextAddress --- not sure if this should even exist for contiguous ones..
    -- not sure if this is the right model for the valid ops
    --validAddress::Form   lay contiguity rank -> Int -> Either String (Shape rank Int)
    --validIndex ::Form   lay contiguity rank -> Shape rank Int -> Either String Int

    -- IMPORTANT NOTE, the NextAddress defined via Next Index seems
    -- that it will only be invoked on strided/discontiguous dense formats
    -- this
    basicNextAddress :: form  -> Address ->  Address
    basicNextAddress =  \form shp ->  basicToAddress form $
      (basicNextIndex form  $ basicToIndex form  shp )
    {-# INLINE basicNextAddress #-}

    basicNextIndex :: form  -> Shape rank Int ->Shape rank Int
    basicNextIndex  = \form shp ->  basicToIndex form  $
       (basicNextAddress form  $ basicToAddress form  shp )
    {-# INLINE  basicNextIndex #-}




    -- one of basicNextAddress and basicNextIndex must always be implemented
#if defined(__GLASGOW_HASKELL_) && __GLASGOW_HASKELL__ >= 707
    {-# MINIMAL  basicToIndex, basicToAddress, (basicNextIndex | basicNextAddress)  #-}
#endif

-----
-----
-----

instance DenseLayout (Format Direct Contiguous (S Z) rep)  (S Z)  where



    {-#INLINE basicToAddress#-}
    basicToAddress   = \ (FormatDirectContiguous _) (j :* _ ) -> Address j

    --basicNextIndex=  undefined -- \ _ x ->  Just $! x + 1
    --note its unchecked!
    {-# INLINE basicToIndex#-}
    basicToIndex =  \ (FormatDirectContiguous _) (Address ix)  -> (ix ) :* Nil

    {-# INLINE basicNextAddress #-}
    basicNextAddress = \ _ addr -> addr + 1





instance DenseLayout (Format Direct Strided (S Z) rep)  (S Z)  where



    {-#INLINE basicToAddress#-}
    basicToAddress   = \ (FormatDirectStrided _ strid) (j :* Nil )->  Address (strid * j)

    {-# INLINE basicNextAddress #-}
    basicNextAddress = \ (FormatDirectStrided _ strid) addr ->  addr + Address strid

    {-# INLINE basicNextIndex#-}
    basicNextIndex =  \ _  (i:* Nil ) ->  (i + 1 :* Nil )


    {-# INLINE basicToIndex#-}
    basicToIndex = \ (FormatDirectStrided _ stride) (Address ix)  -> (ix `div` stride ) :* Nil


-----
-----
-----



-- strideRow :: Shape rank Int,
instance   (Applicative (Shape rank),F.Foldable (Shape rank), Traversable (Shape rank))
    => DenseLayout (Format Row  Contiguous rank rep) rank where


    {-# INLINE basicToAddress #-}
    --basicToAddress = \rs tup -> let !strider =takePrefix $! S.scanr (*) 1 (boundsFormRow rs)
    basicToAddress = \rs tup ->
          let !strider = flip evalState 1 $
                          ---- this is just computing the stride vector
                            flip (S.backwards traverse) (boundsFormRow rs) $
                              \ val ->
                                   do accum <- get ;
                                      put (val * accum) ;
                                      return accum;
                  in Address $! S.foldl'  (+) 0 $! map2 (*) strider tup

    {-# INLINE basicNextAddress#-}
    basicNextAddress = \_ addr -> addr + 1

    {-# INLINE basicToIndex #-}
    basicToIndex  =   \ rs (Address ix) ->
        let !striderShape  =  flip evalState 1 $
                      flip  traverse (boundsFormRow rs) $
                      -- basically accumulating the product of the
                      -- dimensions
                          \ val ->
                               do accum <- get ;
                                  put (val * accum) ;
                                  return accum;
            in
               flip evalState ix $
                  flip (S.backwards traverse)  striderShape $
                  -- want to start from largest stride (which is on the right)
                      \ currentStride ->
                             do remainderIx <- get ;
                                let (!qt,!rm)= quotRem remainderIx currentStride
                                put rm
                                return  qt;




-----
-----

-- strideRow :: Shape rank Int,
instance   (Applicative (Shape rank),F.Foldable (Shape rank), Traversable (Shape rank))
  => DenseLayout (Format Row  InnerContiguous rank rep) rank  where


    {-# INLINE basicToAddress #-}
    basicToAddress = \rs tup ->
                       Address $! S.foldl'  (+) 0 $!
                         map2 (*) (strideFormRowInnerContig rs ) tup

    {-# INLINE basicNextIndex #-}
    basicNextIndex = \ (FormatRowInnerContiguous shape _) ix ->
        --S.map snd $!
        flip evalState 1 $
           flip traverse  ((,) <$> ix <*> shape) $
              \(ixv ,shpv   )->
                  do  carry <-get
                      let (newCarry,modVal)=divMod (carry + ixv) shpv
                      put newCarry
                      return modVal


    {-# INLINE basicToIndex #-}
    basicToIndex  =   \ rs (Address ix) ->   flip evalState ix $
                          flip ( S.backwards traverse)  (strideFormRowInnerContig rs ) $
                              \ currentStride ->
                                     do remainderIx <- get ;
                                        let (!qt,!rm)= quotRem remainderIx currentStride
                                        put rm
                                        return  qt;



---
---
-- strideRow :: Shape rank Int,

instance  (Applicative (Shape rank),F.Foldable (Shape rank), Traversable (Shape rank))
  => DenseLayout (Format Row  Strided rank rep) rank  where



    {-# INLINE basicToAddress #-}
    basicToAddress = \rs tup ->   Address $!
          S.foldl'  (+) 0 $! map2 (*) (strideFormRowStrided rs ) tup

    {-# INLINE basicNextIndex #-}
    basicNextIndex = \ (FormatRowStrided shape _) ix ->
        --S.map snd $!
        flip evalState 1 $
           flip traverse  ((,) <$> ix <*> shape) $
              \(ixv ,shpv   )->
                  do  carry <-get
                      let (newCarry,modVal)=divMod (carry + ixv) shpv
                      put newCarry
                      return modVal


    {-# INLINE basicToIndex #-}
    basicToIndex  =   \ rs (Address ix) ->   flip evalState ix $
                          flip (S.backwards traverse ) (strideFormRowStrided rs ) $
                              \ currentStride ->
                                     do remainderIx <- get ;
                                        let (!qt,!rm)= quotRem remainderIx currentStride
                                        put rm
                                        return  qt;




-----
-----
-----


 -- strideRow :: Shape rank Int,
instance  (Applicative (Shape rank),F.Foldable (Shape rank), Traversable (Shape rank))
  => DenseLayout (Format Column  Contiguous rank rep)  rank where



    {-# INLINE basicToAddress #-}
    basicToAddress = \rs tup -> let !strider = flip evalState 1 $
                                      flip (S.backwards traverse) (boundsColumnContig rs) $
                                        \ val ->
                                               do accum <- get ;
                                                  put (val * accum);
                                                  return accum;
                                in Address $! S.foldl'  (+) 0 $! map2 (*) strider tup

    {-# INLINE basicNextAddress#-}
    basicNextAddress = \_ addr -> addr + 1

    {-# INLINE basicToIndex #-}
    basicToIndex  =   \ rs (Address ix) ->
            let !striderShape  =  flip evalState 1 $
                        flip (S.backwards traverse) (boundsColumnContig rs) $
                                        \ val ->
                                             do accum <- get ;
                                                put (val * accum) ;
                                                return  accum;
                in
                   flip evalState ix $
                          flip  traverse  striderShape $
                              \ currentStride ->
                                     do remainderIx <- get ;
                                        let (!qt,!rm)= quotRem remainderIx currentStride
                                        put rm
                                        return  qt;





 -- strideRow :: Shape rank Int,
instance  (Applicative (Shape rank),F.Foldable (Shape rank), Traversable (Shape rank))
  => DenseLayout (Format Column  InnerContiguous rank rep) rank  where


    {-# INLINE basicToAddress #-}
    basicToAddress    =   \ form tup -> let !strider =   strideFormColumnInnerContig form
                                in Address $! foldl' (+) 0  $! map2 (*) strider tup
    {-# INLINE basicNextIndex #-}
    basicNextIndex = \ (FormatColumnInnerContiguous shape _) ix ->
        --S.map snd $!
        flip evalState 1 $
           flip (S.backwards traverse)  ((,) <$> ix <*> shape) $
              \(ixv ,shpv   )->
                  do  carry <-get
                      let (newCarry,modVal)=divMod (carry + ixv) shpv
                      put newCarry
                      return modVal


    {-# INLINE basicToIndex #-}
    basicToIndex  =   \ rs (Address ix) ->   flip evalState ix $
                          flip S.traverse  (strideFormColumnInnerContig rs ) $
                              \ currentStride ->
                                     do remainderIx <- get ;
                                        let (!qt,!rm)= quotRem remainderIx currentStride
                                        put rm
                                        return  qt;




instance   (Applicative (Shape rank),F.Foldable (Shape rank), Traversable (Shape rank))
  => DenseLayout (Format Column  Strided rank rep) rank where

    {-# INLINE basicToAddress #-}
    basicToAddress    =   \ form tup -> let !strider =   strideFormColumnStrided form
                                in Address $! foldl' (+) 0  $! map2 (*) strider tup

    {-# INLINE basicNextIndex #-}
    basicNextIndex = \ (FormatColumnStrided shape _) ix ->
        --S.map snd $!
        flip evalState 1 $
           flip (S.backwards traverse)  ((,) <$> ix <*> shape) $
              \(ixv ,shpv   )->
                  do  carry <-get
                      let (newCarry,modVal)=divMod (carry + ixv) shpv
                      put newCarry
                      return modVal


    {-# INLINE basicToIndex #-}
    basicToIndex  =   \ rs (Address ix) ->   flip evalState ix $
                          flip S.traverse  (strideFormColumnStrided rs ) $
                              \ currentStride ->
                                     do remainderIx <- get ;
                                        let (!qt,!rm)= quotRem remainderIx currentStride
                                        put rm
                                        return  qt;






{-
*Numerical.Array.Layout> basicToAddress (FormColumn (2 :* 3 :* 7 :* Nil)) (0:* 2 :* 2 :* Nil)
Address 16
*Numerical.Array.Layout> basicToAddress (FormColumn (2 :* 3 :* 7 :* Nil)) (1:* 0 :* 0 :* Nil)
Address 1
*Numerical.Array.Layout> basicToAddress (FormColumn (2 :* 3 :* 7 :* Nil)) (0:* 0 :* 0 :* Nil)
Address 0
*Numerical.Array.Layout> basicToAddress (FormColumn (2 :* 3 :* 7 :* Nil)) (0:* 1 :* 0 :* Nil)
Address 2
*Numerical.Array.Layout> basicToAddress (FormColumn (2 :* 3 :* 7 :* Nil)) (0:* 0 :* 1 :* Nil)
-}


\end{code}
