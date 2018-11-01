{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes, LambdaCase, TupleSections #-}

--------------------------------------------------
--------------------------------------------------

{-| Converting between partial functions and maps.

a (safely-)partial function is isomorphic with a @Map@:

@
'fromFunctionM' . 'toFunctionM' = 'id'
'toFunctionM' . 'fromFunctionM' = 'id'
@

modulo the error thrown.

-}

module Enumerate.Function.Map

  (
   -- * Doctest Context:
   -- $setup

    module Enumerate.Function.Map

  ) where

--------------------------------------------------
-- Imports: (Internal) Project Libraries ---------
--------------------------------------------------

import Enumerate.Types

--------------------------------------------------

import Enumerate.Function.Extra
import Enumerate.Function.Types
import Enumerate.Function.Reify
import Enumerate.Function.Invert

--------------------------------------------------
-- Imports: (External) Dependency Libraries ------
--------------------------------------------------

import "exceptions" Control.Monad.Catch (MonadThrow(..))

--------------------------------------------------
-- Imports: Standard Library ---------------------
--------------------------------------------------

import qualified Data.Map as Map
import           Data.Map (Map)

--------------------------------------------------

import           Control.Exception(PatternMatchFail(..))
import           Data.Maybe (fromJust)

--------------------------------------------------

-- import GHC.TypeLits (Nat, type (^))

--------------------------------------------------
-- DocTest ---------------------------------------
--------------------------------------------------

{- $setup

>>> :set +m
>>> :set -XLambdaCase
>>> import qualified Prelude
>>> :{
let myNotM :: Monad m => Bool -> m Bool
    myNotM False = return True
    myNotM True  = return False
:}

-}

--------------------------------------------------
-- Definitions -----------------------------------
--------------------------------------------------

{- | Convert a map to a function, if the map is total.

>>> Just not_ <- return $ toFunction (Map.fromList [(False,True),(True,False)])
>>> not_ False
True
>>> not_ True
False

-}

toFunction :: (Enumerable a, Ord a) => Map a b -> Maybe (a -> b)
toFunction m = if isMapTotal m then Just f else Nothing
 where

 f = unsafeToFunction m
 --
 -- the cast (unsafeToFunction) is safe.
 -- when the map is total (isMapTotal).

{-# INLINABLE toFunction #-}

--------------------------------------------------

{- | Convert a (safely-)partial function to a map.

Lookup failures are 'throwM'n as a 'PatternMatchFail'.

>>> idPartial = toFunctionM (Map.fromList [(True,True)])
>>> idPartial True
True
>>> idPartial False
*** Exception: toFunctionM

-}

toFunctionM :: (Enumerable a, Ord a) => Map a b -> (Partial a b)
toFunctionM m = f
 where
 f x = maybe (throwM (PatternMatchFail "toFunctionM")) return (Map.lookup x m)

{-# INLINABLE toFunctionM #-}

--------------------------------------------------

{-| Wraps 'Map.lookup'
-}

unsafeToFunction :: (Ord a) => Map a b -> (a -> b)
unsafeToFunction m x = fromJust (Map.lookup x m)

{-# INLINABLE unsafeToFunction #-}

--------------------------------------------------

{-| Refines a partial function, if total.

>>> Just myNot = isTotalM myNotM
>>> myNot False
True
>>> myNot True
False

>>> :{
let uppercasePartial :: (MonadThrow m) => Char -> m Char  -- :: Partial Char Char
    uppercasePartial = \case
     'a' -> return 'A'
     'b' -> return 'B'
     'z' -> return 'Z'
     _   -> failed "uppercasePartial"
in maybe False (const True) $ isTotalM uppercasePartial
:}
False

>>> maybe False (const True) $ isTotalM (return :: Partial Char Char)
True

(with @uppercasePartial@ defined above, and 'Partial' defined internally).

@
'isTotalM' = 'toFunction' . 'fromFunctionM'
@

-}

isTotalM :: (Enumerable a, Ord a) => (Partial a b) -> Maybe (a -> b)
isTotalM f = toFunction (fromFunctionM f)

--------------------------------------------------------------------------------

{-| Wraps 'Map.lookup'.

>>> (unsafeFromList [(False,True),(True,False)]) False
True
>>> (unsafeFromList [(False,True),(True,False)]) True
False

@
'unsafeFromList' = 'unsafeToFunction' . 'Map.fromList'
@

-}

unsafeFromList
 :: (Ord a)
 => [(a,b)]
 -> (a -> b)
unsafeFromList
 = unsafeToFunction . Map.fromList

{-# INLINABLE unsafeFromList #-}

--------------------------------------------------

{-| All functions from @a@ to @b@.

@
'functionEnumerated' ≡ 'mappingEnumeratedAt' 'enumerated' 'enumerated'

-- (modulo 'toFunction')
@

-}

functionEnumerated
 :: (Enumerable a, Enumerable b, Ord a, Ord b)
 => [a -> b]
functionEnumerated = functions
 where
 functions = (unsafeToFunction . Map.fromList) <$> mappings
 mappings = mappingEnumeratedAt enumerated enumerated

--------------------------------------------------

-- | @|b| ^ |a|@
functionCardinality
 :: forall a b proxy. (Enumerable a, Enumerable b)
 => proxy (a -> b)
 -> Natural
functionCardinality _
 = cardinality (Proxy :: Proxy b) ^ cardinality (Proxy :: Proxy a)

{-# INLINABLE functionCardinality #-}

--------------------------------------------------

-- | Are all pairs of outputs the same for the same input? (short-ciruits).
extensionallyEqualTo
 :: (Enumerable a, Eq b)
 => (a -> b)
 -> (a -> b)
 -> Bool
extensionallyEqualTo f g
 = all ((==) <$> f <*> g) enumerated

{-# INLINABLE extensionallyEqualTo #-}

--------------------------------------------------

-- | Is any pair of outputs different for the same input? (short-ciruits).
extensionallyUnequalTo
 :: (Enumerable a, Eq b)
 => (a -> b)
 -> (a -> b)
 -> Bool
extensionallyUnequalTo f g
 = any ((/=) <$> f <*> g) enumerated

{-# INLINABLE extensionallyUnequalTo #-}

--------------------------------------------------

{- | Show all inputs and their outputs, as @'unsafeFromList' [...]@.

Useful for defining (orphan) 'Show' instances for functions.
(See "Enumerate.OrphansFunction").

-}
functionShowsPrec
 :: (Enumerable a, Show a, Show b)
 => Int
 -> (a -> b)
 -> ShowS
functionShowsPrec
 = showsPrecWith "unsafeFromList" reifyFunction

{-# INLINABLE functionShowsPrec #-}

--------------------------------------------------

{-| Display a function as a @case@ expression.

Show /all/ inputs and their outputs, as a @-XLambdaCase@ expression,
i.e. @\\case ...@.

>>> Prelude.putStrLn (displayFunction Prelude.not)
\case
 False -> True
 True -> False

>>> const_True = const True :: Bool -> Bool
>>> Prelude.putStrLn (displayFunction const_True)
\case
 False -> True
 True -> True

-}

displayFunction
  :: (Enumerable a, Show a, Show b)
  => (a -> b) -> String

displayFunction = reifyFunction
             >>> fmap displayCase
             >>> ("\\case" :)
             >>> intercalate "\n" --TODO or, optionally with parameter, a semicolon.

  where

  displayCase (x,y) = intercalate " " ["", show x, "->", show y]

--------------------------------------------------

-- displayPartialFunction
--  :: (Enumerable a, Show a, Show b)
--  => (Partial a b)
--  -> String

--------------------------------------------------

{-| Display a function, if injective, in a "@esac@" expression.

@esac@ is some (pseudo-Haskell) syntax for defining injective functions.
NAMING: "esac" is "case" backwards.

>>> const_True = const True :: Bool -> Bool
>>> Nothing = displayInjective const_True

>>> Just f = displayInjective not
>>> putStrLn f
\esac
 True <- Just False
 False <- Just True
 _ <- Nothing

Calls 'isInjective'.

-}

displayInjective
 :: (Enumerable a, Ord a, Ord b, Show a, Show b)
 => (a -> b)
 -> Maybe String

displayInjective f =

  case isInjective f of
    Nothing -> Nothing
    Just{}  -> Just (go f)

  where

  go  = reifyFunction
    >>> fmap displayCase
    >>> (["\\esac"]++)
    >>> (++ [" _ <- Nothing"])
    >>> intercalate "\n"      --TODO or, optionally with parameter, a semicolon.

  displayCase (x,y) = intercalate " " ["", show y, "<-", show (Just x)]

  -- displayInjective f = go <$> isInjective f
  --
  --   where
  --   go   = reifyFunction
  --      >>> fmap displayCase
  --      >>> ("\\case":)
  --      >>> intercalate "\n"
  --   displayCase = \case
  --    (y, Nothing) ->
  --    (y, Just x)  -> intercalate " " ["", show y, " <- ", show x]

--------------------------------------------------

{-| Construct all mappings, with explicit domain and image.

NOTE:

* @[(a,b)]@ is a "mapping".
* @[[(a,b)]]@ is a list of mappings.

>>> orderingPredicates = mappingEnumeratedAt [LT,EQ,GT] [False,True]
>>> length orderingPredicates
8
>>> import Enumerate.Function.Extra (printMappings)
>>> printMappings orderingPredicates
<BLANKLINE>
(LT,False)
(EQ,False)
(GT,False)
<BLANKLINE>
(LT,False)
(EQ,False)
(GT,True)
<BLANKLINE>
(LT,False)
(EQ,True)
(GT,False)
<BLANKLINE>
(LT,False)
(EQ,True)
(GT,True)
<BLANKLINE>
(LT,True)
(EQ,False)
(GT,False)
<BLANKLINE>
(LT,True)
(EQ,False)
(GT,True)
<BLANKLINE>
(LT,True)
(EQ,True)
(GT,False)
<BLANKLINE>
(LT,True)
(EQ,True)
(GT,True)

where the (total) mapping:

@
[ (LT, False)
, (EQ, False)
, (GT, True)
]
@

is equivalent to the function:

@
\\case
 LT -> False
 EQ -> False
 GT -> True
@

(with 'printMappings' defined internally).

-}

mappingEnumeratedAt :: [a] -> [b] -> [[(a,b)]]           -- TODO diagonalize? performance?
mappingEnumeratedAt as bs = go (crossProduct as bs)
 where

 go []                     = []

 go [somePairs]            = do
  pair <- somePairs
  return$ [pair]

 go (somePairs:theProduct) = do
  pair <- somePairs
  theExponent <- go theProduct
  return$ pair : theExponent

--------------------------------------------------

{-| The cross-product of two lists.

>>> crossOrderingBoolean = crossProduct [LT,EQ,GT] [False,True]
>>> length crossOrderingBoolean
3
>>> length (Prelude.head crossOrderingBoolean)
2
>>> import Enumerate.Function.Extra (printMappings)
>>> printMappings crossOrderingBoolean
<BLANKLINE>
(LT,False)
(LT,True)
<BLANKLINE>
(EQ,False)
(EQ,True)
<BLANKLINE>
(GT,False)
(GT,True)

(with 'printMappings' defined internally).

The length of the outer list is the size of the first set, and
the length of the inner list is the size of the second set.

-}

crossProduct :: [a] -> [b] -> [[(a,b)]]
crossProduct [] _ = []
crossProduct (aValue:theDomain) theCodomain =
 fmap (aValue,) theCodomain : crossProduct theDomain theCodomain

--------------------------------------------------
--------------------------------------------------