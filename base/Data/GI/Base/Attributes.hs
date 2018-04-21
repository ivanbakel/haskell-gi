{-# LANGUAGE GADTs, ScopedTypeVariables, DataKinds, KindSignatures,
  TypeFamilies, TypeOperators, MultiParamTypeClasses, ConstraintKinds,
  UndecidableInstances, FlexibleInstances #-}

-- |
--
-- == Basic attributes interface
--
-- Attributes of an object can be get, set and constructed. For types
-- descending from 'Data.GI.Base.BasicTypes.GObject', properties are
-- encoded in attributes, although attributes are slightly more
-- general (every property of a `Data.GI.Base.BasicTypes.GObject` is an
-- attribute, but we can also have attributes for types not descending
-- from `Data.GI.Base.BasicTypes.GObject`).
--
-- As an example consider a @button@ widget and a property (of the
-- Button class, or any of its parent classes or implemented
-- interfaces) called "label". The simplest way of getting the value
-- of the button is to do
--
-- > value <- getButtonLabel button
--
-- And for setting:
--
-- > setButtonLabel button label
--
-- This mechanism quickly becomes rather cumbersome, for example for
-- setting the "window" property in a DOMDOMWindow in WebKit:
--
-- > win <- getDOMDOMWindowWindow dom
--
-- and perhaps more importantly, one needs to chase down the type
-- which introduces the property:
--
-- > setWidgetSensitive button False
--
-- There is no @setButtonSensitive@, since it is the @Widget@ type
-- that introduces the "sensitive" property.
--
-- == Overloaded attributes
--
-- A much more convenient overloaded attribute resolution API is
-- provided by this module. Getting the value of an object's attribute
-- is straightforward:
--
-- > value <- get button _label
--
-- The definition of @_label@ is basically a 'Proxy' encoding the name
-- of the attribute to get:
--
-- > _label = fromLabelProxy (Proxy :: Proxy "label")
--
-- These proxies can be automatically generated by invoking the code
-- generator with the @-l@ option. The leading underscore is simply so
-- the autogenerated identifiers do not pollute the namespace, but if
-- this is not a concern the autogenerated names (in the autogenerated
-- @GI/Properties.hs@) can be edited as one wishes.
--
-- In addition, for ghc >= 8.0, one can directly use the overloaded
-- labels provided by GHC itself. Using the "OverloadedLabels"
-- extension, the code above can also be written as
--
-- > value <- get button #label
--
-- The syntax for setting or updating an attribute is only slightly more
-- complex. At the simplest level it is just:
--
-- > set button [ _label := value ]
--
-- or for the WebKit example above
--
-- > set dom [_window := win]
--
-- However as the list notation would indicate, you can set or update multiple
-- attributes of the same object in one go:
--
-- > set button [ _label := value, _sensitive := False ]
--
-- You are not limited to setting the value of an attribute, you can also
-- apply an update function to an attribute's value. That is the function
-- receives the current value of the attribute and returns the new value.
--
-- > set spinButton [ _value :~ (+1) ]
--
-- There are other variants of these operators, see 'AttrOp'
-- below. ':=>' and ':~>' are like ':=' and ':~' but operate in the
-- 'IO' monad rather than being pure.
--
-- Attributes can also be set during construction of a
-- `Data.GI.Base.BasicTypes.GObject` using `Data.GI.Base.Properties.new`
--
-- > button <- new Button [_label := "Can't touch this!", _sensitive := False]
--
-- In addition for value being set/get having to have the right type,
-- there can be attributes that are read-only, or that can only be set
-- during construction with `Data.GI.Base.Properties.new`, but cannot be
-- `set` afterwards. That these invariants hold is also checked during
-- compile time.
--
-- == Nullable atributes
--
-- Whenever the attribute is represented as a pointer in the C side,
-- it is often the case that the underlying C representation admits or
-- returns @NULL@ as a valid value for the property. In these cases
-- the `get` operation may return a `Maybe` value, with `Nothing`
-- representing the @NULL@ pointer value (notable exceptions are
-- `Data.GI.Base.BasicTypes.GList` and
-- `Data.GI.Base.BasicTypes.GSList`, for which @NULL@ is represented
-- simply as he empty list). This can be overriden in the
-- introspection data, since sometimes attributes are non-nullable,
-- even if the type would allow for @NULL@.
--
-- For convenience, in nullable cases the `set` operation will by
-- default /not/ take a `Maybe` value, but rather assume that the
-- caller wants to set a non-@NULL@ value. If setting a @NULL@ value
-- is desired, use `clear` as follows
--
-- > clear object _propName
--
module Data.GI.Base.Attributes (
  AttrInfo(..),

  AttrOpTag(..),

  AttrOp(..),
  AttrOpAllowed,

  AttrGetC,
  AttrSetC,
  AttrConstructC,
  AttrClearC,

  get,
  set,
  clear,

  AttrLabelProxy(..)
  ) where

import Control.Monad.IO.Class (MonadIO, liftIO)

import Data.Proxy (Proxy(..))

import Data.GI.Base.GValue (GValueConstruct)
import Data.GI.Base.Overloading (HasAttributeList,
                                 ResolveAttribute, IsLabelProxy(..))

import GHC.TypeLits
import GHC.Exts (Constraint)

#if MIN_VERSION_base(4,9,0)
import GHC.OverloadedLabels (IsLabel(..))
#endif

infixr 0 :=,:~,:=>,:~>

-- | A proxy for attribute labels.
data AttrLabelProxy (a :: Symbol) = AttrLabelProxy

-- | Support for overloaded labels.
instance a ~ x => IsLabelProxy x (AttrLabelProxy a) where
    fromLabelProxy _ = AttrLabelProxy

#if MIN_VERSION_base(4,10,0)
instance a ~ x => IsLabel x (AttrLabelProxy a) where
    fromLabel = AttrLabelProxy
#elif MIN_VERSION_base(4,9,0)
instance a ~ x => IsLabel x (AttrLabelProxy a) where
    fromLabel _ = AttrLabelProxy
#endif

-- | Info describing an attribute.
class AttrInfo (info :: *) where
    -- | The operations that are allowed on the attribute.
    type AttrAllowedOps info :: [AttrOpTag]
    -- | Constraint on the value being set.
    type AttrSetTypeConstraint info :: * -> Constraint
    -- | Constraint on the type for which we are allowed to
    -- create\/set\/get the attribute.
    type AttrBaseTypeConstraint info :: * -> Constraint
    -- | Type returned by `attrGet`.
    type AttrGetType info
    -- | Name of the attribute.
    type AttrLabel info :: Symbol
    -- | Type which introduces the attribute.
    type AttrOrigin info
    -- | Get the value of the given attribute.
    attrGet :: AttrBaseTypeConstraint info o =>
               Proxy info -> o -> IO (AttrGetType info)
    -- | Set the value of the given attribute, after the object having
    -- the attribute has already been created.
    attrSet :: (AttrBaseTypeConstraint info o,
                AttrSetTypeConstraint info b) =>
               Proxy info -> o -> b -> IO ()
    -- | Set the value of the given attribute to @NULL@ (for nullable
    -- attributes).
    attrClear :: AttrBaseTypeConstraint info o =>
                 Proxy info -> o -> IO ()
    -- | Build a `GValue` representing the attribute.
    attrConstruct :: (AttrBaseTypeConstraint info o,
                      AttrSetTypeConstraint info b) =>
                     Proxy info -> b -> IO (GValueConstruct o)

-- | Result of checking whether an op is allowed on an attribute.
data OpAllowed tag attrName definingType useType =
    OpIsAllowed
#if !MIN_VERSION_base(4,9,0)
        | AttrOpNotAllowed Symbol tag Symbol definingType Symbol attrName
#endif

#if MIN_VERSION_base(4,9,0)
type family TypeOriginInfo definingType useType :: ErrorMessage where
    TypeOriginInfo definingType definingType =
        'Text "‘" ':<>: 'ShowType definingType ':<>: 'Text "’"
    TypeOriginInfo definingType useType =
        'Text "‘" ':<>: 'ShowType useType ':<>:
        'Text "’ (inherited from parent type ‘" ':<>:
        'ShowType definingType ':<>: 'Text "’)"
#endif

-- | Look in the given list to see if the given `AttrOp` is a member,
-- if not return an error type.
type family AttrOpIsAllowed (tag :: AttrOpTag) (ops :: [AttrOpTag]) (label :: Symbol) (definingType :: *) (useType :: *) :: OpAllowed AttrOpTag Symbol * * where
    AttrOpIsAllowed tag '[] label definingType useType =
#if !MIN_VERSION_base(4,9,0)
        'AttrOpNotAllowed "Error: operation " tag " not allowed for attribute " definingType "." label
#else
        TypeError ('Text "Attribute ‘" ':<>: 'Text label ':<>:
                   'Text "’ for type " ':<>:
                   TypeOriginInfo definingType useType ':<>:
                   'Text " is not " ':<>:
                   'Text (AttrOpText tag) ':<>: 'Text ".")
#endif
    AttrOpIsAllowed tag (tag ': ops) label definingType useType = 'OpIsAllowed
    AttrOpIsAllowed tag (other ': ops) label definingType useType = AttrOpIsAllowed tag ops label definingType useType

-- | Whether a given `AttrOpTag` is allowed on an attribute, given the
-- info type.
type family AttrOpAllowed (tag :: AttrOpTag) (info :: *) (useType :: *) :: Constraint where
    AttrOpAllowed tag info useType =
        AttrOpIsAllowed tag (AttrAllowedOps info) (AttrLabel info) (AttrOrigin info) useType ~ 'OpIsAllowed

-- | Possible operations on an attribute.
data AttrOpTag = AttrGet | AttrSet | AttrConstruct | AttrClear

#if MIN_VERSION_base(4,9,0)
-- | A user friendly description of the `AttrOpTag`, useful when
-- printing type errors.
type family AttrOpText (tag :: AttrOpTag) :: Symbol where
    AttrOpText 'AttrGet = "gettable"
    AttrOpText 'AttrSet = "settable"
    AttrOpText 'AttrConstruct = "constructible"
    AttrOpText 'AttrClear = "nullable"
#endif

-- | Constraint on a @obj@\/@attr@ pair so that `set` works on values
-- of type @value@.
type AttrSetC info obj attr value = (HasAttributeList obj,
                                     info ~ ResolveAttribute attr obj,
                                     AttrInfo info,
                                     AttrBaseTypeConstraint info obj,
                                     AttrOpAllowed 'AttrSet info obj,
                                     (AttrSetTypeConstraint info) value)

-- | Constraint on a @obj@\/@value@ pair so that `new` works on values
-- of type @@value@.
type AttrConstructC info obj attr value = (HasAttributeList obj,
                                           info ~ ResolveAttribute attr obj,
                                           AttrInfo info,
                                           AttrBaseTypeConstraint info obj,
                                           AttrOpAllowed 'AttrConstruct info obj,
                                           (AttrSetTypeConstraint info) value)

-- | Constructors for the different operations allowed on an attribute.
data AttrOp obj (tag :: AttrOpTag) where
    -- | Assign a value to an attribute
    (:=)  :: (HasAttributeList obj,
              info ~ ResolveAttribute attr obj,
              AttrInfo info,
              AttrBaseTypeConstraint info obj,
              AttrOpAllowed tag info obj,
              (AttrSetTypeConstraint info) b) =>
             AttrLabelProxy (attr :: Symbol) -> b -> AttrOp obj tag
    -- | Assign the result of an IO action to an attribute
    (:=>) :: (HasAttributeList obj,
              info ~ ResolveAttribute attr obj,
              AttrInfo info,
              AttrBaseTypeConstraint info obj,
              AttrOpAllowed tag info obj,
              (AttrSetTypeConstraint info) b) =>
             AttrLabelProxy (attr :: Symbol) -> IO b -> AttrOp obj tag
    -- | Apply an update function to an attribute
    (:~)  :: (HasAttributeList obj,
              info ~ ResolveAttribute attr obj,
              AttrInfo info,
              AttrBaseTypeConstraint info obj,
              tag ~ 'AttrSet,
              AttrOpAllowed 'AttrSet info obj,
              AttrOpAllowed 'AttrGet info obj,
              (AttrSetTypeConstraint info) b,
              a ~ (AttrGetType info)) =>
             AttrLabelProxy (attr :: Symbol) -> (a -> b) -> AttrOp obj tag
    -- | Apply an IO update function to an attribute
    (:~>) :: (HasAttributeList obj,
              info ~ ResolveAttribute attr obj,
              AttrInfo info,
              AttrBaseTypeConstraint info obj,
              tag ~ 'AttrSet,
              AttrOpAllowed 'AttrSet info obj,
              AttrOpAllowed 'AttrGet info obj,
              (AttrSetTypeConstraint info) b,
              a ~ (AttrGetType info)) =>
             AttrLabelProxy (attr :: Symbol) -> (a -> IO b) -> AttrOp obj tag

-- | Set a number of properties for some object.
set :: forall o m. MonadIO m => o -> [AttrOp o 'AttrSet] -> m ()
set obj = liftIO . mapM_ app
 where
   resolve :: AttrLabelProxy attr -> Proxy (ResolveAttribute attr o)
   resolve _ = Proxy

   app :: AttrOp o 'AttrSet -> IO ()
   app (attr :=  x) = attrSet (resolve attr) obj x
   app (attr :=> x) = x >>= attrSet (resolve attr) obj
   app (attr :~  f) = attrGet (resolve attr) obj >>=
                      \v -> attrSet (resolve attr) obj (f v)
   app (attr :~> f) = attrGet (resolve attr) obj >>= f >>=
                      attrSet (resolve attr) obj

-- | Constraints on a @obj@\/@attr@ pair so `get` is possible,
-- producing a value of type @result@.
type AttrGetC info obj attr result = (HasAttributeList obj,
                                      info ~ ResolveAttribute attr obj,
                                      AttrInfo info,
                                      (AttrBaseTypeConstraint info) obj,
                                      AttrOpAllowed 'AttrGet info obj,
                                      result ~ AttrGetType info)

-- | Get the value of an attribute for an object.
get :: forall info attr obj result m.
       (AttrGetC info obj attr result, MonadIO m) =>
        obj -> AttrLabelProxy (attr :: Symbol) -> m result
get o _ = liftIO $ attrGet (Proxy :: Proxy info) o

-- | Constraint on a @obj@\/@attr@ pair so that `clear` is allowed.
type AttrClearC info obj attr = (HasAttributeList obj,
                                 info ~ ResolveAttribute attr obj,
                                 AttrInfo info,
                                 (AttrBaseTypeConstraint info) obj,
                                 AttrOpAllowed 'AttrClear info obj)

-- | Set a nullable attribute to @NULL@.
clear :: forall info attr obj m.
         (AttrClearC info obj attr, MonadIO m) =>
         obj -> AttrLabelProxy (attr :: Symbol) -> m ()
clear o _ = liftIO $ attrClear (Proxy :: Proxy info) o