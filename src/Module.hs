{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
module Module (
    Module(..)
  , moduleName
  , moduleImports
  , moduleExports
  , moduleBody
  , CompleteModule(..)
  , Decl(..)
  , Imports
  , noImports
  , Exports
  , getExport
  , addExport
  , noExports
  , forExports
  , forExports_
  , ModulePtr
  , newModulePtr
  , ModBodyPtr
  , newModBodyPtr
  , ModuleBodyF(..)
  , SplitModuleBody(..)
  , DeclPtr
  , newDeclPtr
  ) where

import Control.Lens
import Data.Functor
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import Data.Unique

import Binding
import Core
import ModuleName
import Phase
import Syntax

newtype ModulePtr = ModulePtr Unique
  deriving (Eq, Ord)

newModulePtr :: IO ModulePtr
newModulePtr = ModulePtr <$> newUnique

newtype Imports = Imports (Map ModuleName (Map Phase (Set Text)))
  deriving Show

instance Phased Imports where
  shift i (Imports imports) = Imports (Map.map (Map.mapKeys (shift i)) imports)

noImports :: Imports
noImports = Imports Map.empty

instance Semigroup Imports where
  Imports i1 <> Imports i2 = Imports (Map.unionWith (Map.unionWith Set.union) i1 i2)

instance Monoid Imports where
  mempty = noImports
  mappend = (<>)

newtype Exports = Exports (Map Phase (Map Text Binding))
  deriving Show

instance Phased Exports where
  shift i (Exports exports) = Exports $ Map.mapKeys (shift i) exports

instance Semigroup Exports where
  Exports m1 <> Exports m2 = Exports $ Map.unionWith (flip (<>)) m1 m2

instance Monoid Exports where
  mempty = noExports
  mappend = (<>)

forExports :: Applicative f => (Phase -> Text -> Binding -> f a) -> Exports -> f [a]
forExports act (Exports todo) =
  let contents = [(p, n, b) | (p, m) <- Map.toList todo, (n, b) <- Map.toList m]
  in traverse (\(x,y,z) -> act x y z) contents

forExports_ :: Applicative f => (Phase -> Text -> Binding -> f a) -> Exports -> f ()
forExports_ act es = forExports act es $> ()

getExport :: Phase -> Text -> Exports -> Maybe Binding
getExport p x (Exports es) = view (at p) es >>= view (at x)

addExport :: Phase -> Text -> Binding -> Exports -> Exports
addExport p x b (Exports es) = Exports $ over (at p) (Just . ins) es
  where
    ins Nothing = Map.singleton x b
    ins (Just m) = Map.insert x b m

noExports :: Exports
noExports = Exports Map.empty

data Module f a = Module
  { _moduleName :: ModuleName
  , _moduleImports :: !Imports
  , _moduleBody :: f a
  , _moduleExports :: !Exports
  }
  deriving (Functor, Show)
makeLenses ''Module

data CompleteModule = Expanded !(Module [] (Decl Core)) | KernelModule Phase
  deriving Show

instance Phased CompleteModule where
  shift i (Expanded m) = Expanded (shift i m)
  shift i (KernelModule p) = KernelModule (shift i p)

instance (Functor f, Phased a) => Phased (Module f a) where
  shift i =
    over moduleImports (shift i) .
    over moduleExports (shift i) .
    over moduleBody (fmap (shift i))


newtype DeclPtr = DeclPtr Unique
  deriving (Eq, Ord)

newDeclPtr :: IO DeclPtr
newDeclPtr = DeclPtr <$> newUnique

data Decl a
  = Define Ident Var a
  | DefineMacros [(Ident, a)]
  | Meta (Decl a)
  | Example a
  | Import ModuleName Ident
  | Export Ident
  deriving (Functor, Show)

instance Phased a => Phased (Decl a) where
  shift i = fmap (shift i)

newtype ModBodyPtr = ModBodyPtr Unique
  deriving (Eq, Ord)

newModBodyPtr :: IO ModBodyPtr
newModBodyPtr = ModBodyPtr <$> newUnique


data ModuleBodyF decl next = Done | Decl decl next

data SplitModuleBody a = SplitModuleBody
  { _splitModuleRoot :: ModBodyPtr
  , _splitModuleDescendents :: Map ModBodyPtr (ModuleBodyF a ModBodyPtr)
  }



