{-# LANGUAGE TypeOperators, LambdaCase, EmptyCase, TypeFamilies, FlexibleContexts #-}
{-# LANGUAGE DeriveGeneric  #-}-- TODO example module 

module Data.MemoTrie.Generic where 

import Data.MemoTrie

import           GHC.Generics
import Control.Arrow (first) 


{-| "unlifted" generic representation. (i.e. is a nullary type constructor). 

-}
type Reg a = Rep a () 

instance HasTrie (V1 x) where
 data (V1 x :->: b) = V1Trie 
 trie f = V1Trie 
 untrie V1Trie = \case
 enumerate V1Trie = [] 

instance HasTrie (U1 x) where
 data (U1 x :->: b) = U1Trie b 
 trie f = U1Trie (f U1)
 untrie (U1Trie b) = \case
  U1 -> b                       -- TODO strictness? 
 enumerate (U1Trie b) = [(U1, b)] 

instance (HasTrie (f x), HasTrie (g x)) => HasTrie ((f :+: g) x) where
 data ((f :+: g) x :->: b) = SumTrie (f x :->: b) (g x :->: b)
 trie f = SumTrie (trie (f . L1)) (trie (f . R1))
 untrie (SumTrie tl tr) = \case
  L1 a -> (untrie tl) a 
  R1 a -> (untrie tr) a 

 enumerate (SumTrie tl tr) = _enumerateWith L1 tl `weave` _enumerateWith R1 tr
  where 

  weave :: [a] -> [a] -> [a]
  [] `weave` as = as
  as `weave` [] = as
  (a:as) `weave` bs = a : (bs `weave` as)

instance (HasTrie a) => HasTrie (K1 i a x) where
 data (K1 i a x :->: b) = K1Trie (a :->: b) 
 trie f = K1Trie (trie (f . K1)) 
 untrie (K1Trie t) = \case
  K1 a -> (untrie t) a 
 enumerate (K1Trie t) = _enumerateWith K1 t 

instance (HasTrie (f x)) => HasTrie (M1 i t f x) where
 data (M1 i t f x :->: b) = M1Trie (f x :->: b) 
 trie f = M1Trie (trie (f . M1)) 
 untrie (M1Trie t) = \case
  M1 a -> (untrie t) a  
 enumerate (M1Trie t) = _enumerateWith M1 t 


trieGeneric
 :: (Generic a, HasTrie (Reg a))
 => ((Reg a :->: b) -> (a :->: b))
 -> (a -> b)
 -> (a :->: b)
trieGeneric theConstructor f = theConstructor (trie (f . to))

untrieGeneric
 :: (Generic a, HasTrie (Reg a))
 => ((a :->: b) -> (Reg a :->: b))
 -> (a :->: b)
 -> (a -> b)
untrieGeneric theDestructor t = \a -> (untrie (theDestructor t)) (from a)

enumerateGeneric 
 :: (Generic a, HasTrie (Reg a))
 => ((a :->: b) -> (Reg a :->: b))
 -> (a :->: b)
 -> [(a, b)]
enumerateGeneric theDestructor t = _enumerateWith to (theDestructor t) 

_enumerateWith :: (HasTrie a) => (a -> a') -> (a :->: b) -> [(a', b)]
_enumerateWith f = (fmap.first) f . enumerate


data MyContext
 = GlobalContext  
 | EmacsContext
 | ChromeContext
 deriving (Generic) 

instance HasTrie MyContext where
 newtype (MyContext :->: b) = MyContextTrie { unMyContextTrie :: Rep MyContext () :->: b } 
 trie = trieGeneric MyContextTrie 
 untrie = untrieGeneric unMyContextTrie
 enumerate = enumerateGeneric unMyContextTrie

{-| 

e.g. 

@
makeHasTrie ''Example 
@


import Language.Haskell.TH 

makeHasTrie :: Name -> Q [Dec]
makeHasTrie t = do 
 [d| instance HasTrie $theName where
       newtype ($theName :->: b) = $theConstructor { $theDestructor :: Rep $theName () :->: b } 
       trie = trieGeneric $theConstructor 
       untrie = untrieGeneric $theDestructor |] 

 where 
 s = nameBase t 
 theName = return$ t 
 theConstructor = return$ mkName t 
 theDestructor = return$ mkName ("un" ++ t)

-} 
