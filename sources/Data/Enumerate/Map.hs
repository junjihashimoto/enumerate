{-# LANGUAGE RankNTypes, LambdaCase #-}
{-| converting between partial functions and maps.  

>>> :set +m

-}
module Data.Enumerate.Map where
import Data.Enumerate.Types
import Data.Enumerate.Reify 

import Control.Monad.Catch (MonadThrow(..))
import           Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NonEmpty
import Data.Semigroup                   ((<>))

import qualified Data.Map as Map
import           Data.Map (Map)
import qualified Data.Set as Set
import           Data.Set (Set)
import           Data.Maybe (fromJust, mapMaybe, listToMaybe) 


{- | convert a total function to a map. 

@
>>> fromFunction 'not' 
fromList [(False,True),(True,False)]
@

-}
fromFunction :: (Enumerable a, Ord a) => (a -> b) -> Map a b
fromFunction f = fromFunctionM (return.f) 
{-# INLINABLE fromFunction #-}

{- | convert a (safely-)partial function to a map. 

-}
fromFunctionM :: (Enumerable a, Ord a) => (forall m. MonadThrow m => a -> m b) -> Map a b
fromFunctionM f = Map.fromList (reifyFunctionM f)
{-# INLINABLE fromFunctionM #-}

{- | convert a map to a function, if the map is total. 

@
>>> let Just not' = toFunction (Map.fromList [(False,True),(True,False)])
>>> not' False 
True 
@

-} 
toFunction :: (Enumerable a, Ord a) => Map a b -> Maybe (a -> b)
toFunction m = if isMapTotal m then Just f else Nothing 
 where f x = fromJust (Map.lookup x m) -- won't fail
{-# INLINABLE toFunction #-}

{-| does the map contain every key in its domain? 

>>> isMapTotal (Map.fromList [(False,True),(True,False)]) 
True 

>>> isMapTotal (Map.fromList [('a',0)]) 
False 

-}
isMapTotal :: (Enumerable a, Ord a) => Map a b -> Bool
isMapTotal m = all (\x -> Map.member x m) enumerated 

{-| safely invert any map. 

-}
invertMap :: (Ord a, Ord b) => Map a b -> Map b (NonEmpty a) 
invertMap m = Map.fromListWith (<>) [(b, a:|[]) | (a, b) <- Map.toList m]

{-| refines the partial function, if total.

>>> :{ 
let myNotM :: Monad m => Bool -> m Bool
    myNotM False = return True 
    myNotM True  = return False 
:} 
>>> let Just myNot = isTotalM myNotM
>>> myNot False 
True

-}
isTotalM :: (Enumerable a, Ord a) => (forall m. MonadThrow m => a -> m b) -> Maybe (a -> b) 
isTotalM f = (toFunction) (fromFunctionM f)

{-| the codomain (not the range) of a total function. 

@codomainM f = map f 'enumerated'@

includes duplicates.  

-}
codomain :: (Enumerable a) => (a -> b) -> [b] 
codomain f = map f enumerated

{-| the codomain (not the range) of a partial function. 

@codomainM f = mapMaybe f 'enumerated'@

includes duplicates.  

-}
codomainM :: (Enumerable a) => (forall m. MonadThrow m => a -> m b) -> [b] 
codomainM f = mapMaybe f enumerated

{-| invert a total function.

@(invert f) b@ is: 

* @[]@ wherever @f@ is not surjective 
* @(_:_)@ wherever @f@ is not injective 

@invert f = 'invertM' (return.f)@

-}
invert :: (Enumerable a, Ord a, Ord b) => (a -> b) -> (b -> [a])
invert f = invertM (return.f) 

{-| invert a partial function.

@(invertM f) b@ is: 

* @[]@ wherever @f@ is partial 
* @[]@ wherever @f@ is not surjective 
* @(_:_)@ wherever @f@ is not injective 

a @Map@ is stored internally, with as many keys as the 'codomain' of @f@. 

see also 'isBijective'.

-}
invertM :: (Enumerable a, Ord a, Ord b) => (forall m. MonadThrow m => a -> m b) -> (b -> [a])
invertM f = g
 where
 g b = maybe [] NonEmpty.toList (Map.lookup b m)
 m = invertMap (fromFunctionM f) -- share the map 

{-| 

-}
getJectivityM :: (Enumerable a, Enumerable b, Ord a, Ord b) => (forall m. MonadThrow m => a -> m b) -> Maybe Jectivity 
getJectivityM f
 = case isBijectiveM f of       -- TODO pick the right Monoid, who upending picks the first non-nothing 
    Just{}  -> Just Bijective
    Nothing -> case isInjectiveM f of
                Just{}  -> Just Injective 
                Nothing -> case isSurjectiveM f of
                            Just{}  -> Just Surjective
                            Nothing -> Nothing 


{-| returns the inverse of the injection, if injective.

refines @(b -> [a])@ (i.e. invert\'s' type) to @(b -> Maybe a)@. 

unlike 'isBijectiveM', doesn't need an @(Enumerable b)@ constraint. this helps when you want to ensure a function into an infinite type (e.g. 'show') is injective. and still reasonably efficient, given the @(Ord b)@ constraint. 

can short-circuit. 

-}
isInjectiveM :: (Enumerable a, Ord a, Ord b) => (forall m. MonadThrow m => a -> m b) -> Maybe (b -> Maybe a)
isInjectiveM f = do             -- TODO make it "correct by construction", rather than explicit validation 
 _bs <- isUnique (codomainM f)   -- Map.fromListWith (<>) [(b, a:|[]) | (a, b) <- Map.toList m]
 return g 
 where
 g = listToMaybe . invertM f

{-| converts the list into a set, if it has no duplicates. 

-}
isUnique :: (Ord a) => [a] -> Maybe (Set a) 
isUnique l = if length l == length s then Nothing else Just s -- TODO make efficient, maybe single pass with Control.Foldl
 where
 s = Set.fromList l

{-| returns the inverse of the surjection, if surjective.

refines @(b -> [a])@ (i.e. invert\'s' type) to @(b -> NonEmpty a)@. 

can short-circuit. 

-}
isSurjectiveM :: (Enumerable a, Enumerable b, Ord a, Ord b) => (forall m. MonadThrow m => a -> m b) -> Maybe (b -> NonEmpty a)
isSurjectiveM f =  -- TODO make it "correct by construction", rather than explicit validation 
 if (Set.fromList enumerated) == (Set.fromList (codomainM f))
 then Just g
 else Nothing
 where
 g = NonEmpty.fromList . invertM f  -- safe, by validation 

{-| returns the inverse of the bijection, if bijective.

refines @(b -> [a])@ (i.e. invert\'s' type) to @(b -> a)@. 

can short-circuit. 

-}
isBijectiveM :: (Enumerable a, Enumerable b, Ord a, Ord b) => (forall m. MonadThrow m => a -> m b) -> Maybe (b -> a)
isBijectiveM f = do 
 fIn    <- isInjectiveM f
 _fSur  <- isSurjectiveM f --   TODO avoid re-computing invertM. isInjectiveWithM isSurjectiveWithM
 let fBi = (fromJust . fIn)  -- safe, because the intersection of "zero or one" with "one or more" is "one" 
 return fBi
-- let fOp = invertMap (fromFunctionM f) -- share the map 
