{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE FlexibleContexts, FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}

{-# OPTIONS_GHC -w #-}

import Test.QuickCheck
import Test.QuickCheck.Monadic
import Control.Monad
import qualified Data.IntSet as S
import qualified Data.Vector.Unboxed as U
import Data.IORef

import Apecs
import Apecs.Types
import Apecs.Util
import qualified Apecs.Stores as S
import qualified Apecs.Logs as S

type Vec = (Double, Double)

---

newtype Position = Position Vec deriving (Arbitrary, Eq, Show)
instance Component Position where
  type Storage Position = S.Logger (S.FromPure Members) (S.Map Position)

newtype CachePos = CachePos Vec deriving (Arbitrary, Eq, Show)
instance Component CachePos where
  type Storage CachePos = S.Cache 1 (S.Map CachePos)


newtype Velocity = Velocity Vec deriving (Arbitrary, Eq, Show)
instance Component Velocity where
  type Storage Velocity = S.Map Velocity


data TestFlag = TestFlag
instance Arbitrary TestFlag where arbitrary = return TestFlag
instance S.Flag TestFlag where flag = TestFlag
instance Component TestFlag where
  type Storage TestFlag = S.Set TestFlag


newtype Members c = Members S.IntSet
instance S.PureLog Members c where
  pureEmpty = Members mempty
  pureOnSet (Entity e) _ _ (Members s) = Members $ S.insert e s
  pureOnDestroy (Entity e) _ (Members s) = Members $ S.delete e s

newtype RandomEntity a = RandomEntity (Entity a) deriving (Eq, Show)
instance Arbitrary (RandomEntity a) where
  arbitrary = RandomEntity . Entity . abs <$> arbitrary

newtype W1 c = W1 {w1c1 :: (Storage c)}
instance Component c => Has (W1 c) c where getStore = System $ asks w1c1

data W2 a b = W2 { w2c1 :: Storage a , w2c2 :: Storage b }
instance (Component a, Component b) => Has (W2 a b) a where getStore = System $ asks w2c1
instance (Component a, Component b) => Has (W2 a b) b where getStore = System $ asks w2c2

counter :: [CachePos] -> CachePos -> Property
counter cs c = monadicIO $ run f >>= assert
  where
    f = do
      w :: W2 CachePos EntityCounter <- W2 <$> initStore <*> initCounter
      runWith w $ do
        forM_ cs newEntity
        e <- newEntity c
        Safe r <- get e
        return (r == Just c)

getSetPos :: [(RandomEntity Position, Position)] -> RandomEntity Position -> Position -> Property
getSetPos cs (RandomEntity e) p = monadicIO $ run f >>= assert
  where
    f = do
      w :: Storage Position <- initStore
      runWith (W1 w) $ do
        forM_ cs $ \(RandomEntity ety, pos) -> set ety pos
        set e p
        Safe r <- get e
        Slice sl1 :: Slice Position <- owners
        S.FromPure ref :: S.FromPure Members Position <- S.getLog
        Members set <- liftIO$ readIORef ref
        return (r == Just p && sl1 == U.fromList (S.toList set))

getSetVCPos :: [(RandomEntity (Velocity, CachePos), (Velocity, CachePos))] -> RandomEntity (Velocity, CachePos) -> (Velocity, CachePos) -> Property
getSetVCPos cs (RandomEntity e) (v,p) = monadicIO $ run f >>= assert
  where
    f = do
      wp :: Storage CachePos <- initStore
      wv :: Storage Velocity <- initStore
      runWith (W2 wp wv) $ do
        forM_ cs $ \(RandomEntity ety, pos) -> set ety pos
        set e (v,p)
        Safe r <- get e
        return (r == (Just v, Just p))

cmapVP :: [(RandomEntity (Velocity, CachePos), (Velocity, CachePos))] -> RandomEntity (Velocity, CachePos) -> (Velocity, CachePos) -> Property
cmapVP cs (RandomEntity e) (v,p) = monadicIO $ run f >>= assert
  where
    f = do
      let swapP (CachePos (x,y)) = CachePos (y,x)
          swapV (Velocity (x,y)) = Velocity (y,x)
      wp :: Storage CachePos <- initStore
      wv :: Storage Velocity <- initStore
      runWith (W2 wp wv) $ do
        forM_ cs $ \(RandomEntity ety, pos) -> set ety pos
        set e (v,p)
        cmap $ \(v,p) -> (swapV v, swapP p)
        Safe r <- get e
        return (r == (Just $ swapV v, Just $ swapP p))

main = do
  quickCheck getSetPos
  quickCheck getSetVCPos
  quickCheck cmapVP
  quickCheck counter
