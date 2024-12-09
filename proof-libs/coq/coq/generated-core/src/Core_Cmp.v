(* File automatically generated by Hacspec *)
From Coq Require Import ZArith.
Require Import List.
Import List.ListNotations.
Open Scope Z_scope.
Open Scope bool_scope.
Require Import Ascii.
Require Import String.
Require Import Coq.Floats.Floats.
From RecordUpdate Require Import RecordSet.
Import RecordSetNotations.

(* From Core Require Import Core. *)

From Core Require Import Core_Option (t_Option).
Export Core_Option (t_Option).

Definition discriminant_Ordering_Equal :=
  0.

Definition discriminant_Ordering_Greater :=
  1.

Inductive t_Ordering : Type :=
| Ordering_Less
| Ordering_Equal
| Ordering_Greater.
Arguments Ordering_Less.
Arguments Ordering_Equal.
Arguments Ordering_Greater.

Definition impl__Ordering__is_eq (self : t_Ordering) : bool :=
  match self with
  | Ordering_Equal =>
    true
  | _ =>
    false
  end.

Definition impl__Ordering__is_gt (self : t_Ordering) : bool :=
  match self with
  | Ordering_Greater =>
    true
  | _ =>
    false
  end.

Definition impl__Ordering__is_lt (self : t_Ordering) : bool :=
  match self with
  | Ordering_Less =>
    true
  | _ =>
    false
  end.

Definition impl__Ordering__reverse (self : t_Ordering) : t_Ordering :=
  match self with
  | Ordering_Less =>
    Ordering_Greater
  | Ordering_Equal =>
    Ordering_Equal
  | Ordering_Greater =>
    Ordering_Less
  end.

Definition discriminant_Ordering_Less :=
  -1.

Definition t_Ordering_cast_to_repr (x : t_Ordering) :=
  match x with
  | Ordering_Less =>
    discriminant_Ordering_Less
  | Ordering_Equal =>
    discriminant_Ordering_Equal
  | Ordering_Greater =>
    discriminant_Ordering_Greater
  end.

Class t_PartialEq (v_Self : Type) (v_Rhs : Type) : Type :=
  {
    PartialEq_f_eq : v_Self -> v_Rhs -> bool;
    PartialEq_f_ne : v_Self -> v_Rhs -> bool;
  }.
Arguments t_PartialEq (_) (_).

Definition impl__Ordering__is_ge (self : t_Ordering) : bool :=
  negb (match self with
  | Ordering_Less =>
    true
  | _ =>
    false
  end).

Definition impl__Ordering__is_le (self : t_Ordering) : bool :=
  negb (match self with
  | Ordering_Greater =>
    true
  | _ =>
    false
  end).

Definition impl__Ordering__is_ne (self : t_Ordering) : bool :=
  negb (match self with
  | Ordering_Equal =>
    true
  | _ =>
    false
  end).

#[global] Instance t_PartialEq_603824491 : t_PartialEq ((t_Ordering)) ((t_Ordering)) :=
  {
    PartialEq_f_eq := fun  (self : t_Ordering) (other : t_Ordering)=>
      match self with
      | Ordering_Less =>
        match other with
        | Ordering_Less =>
          true
        | _ =>
          false
        end
      | Ordering_Equal =>
        match other with
        | Ordering_Equal =>
          true
        | _ =>
          false
        end
      | Ordering_Greater =>
        match other with
        | Ordering_Greater =>
          true
        | _ =>
          false
        end
      end;
    PartialEq_f_ne := fun  (self : t_Ordering) (other : t_Ordering)=>
      negb (match self with
      | Ordering_Less =>
        match other with
        | Ordering_Less =>
          true
        | _ =>
          false
        end
      | Ordering_Equal =>
        match other with
        | Ordering_Equal =>
          true
        | _ =>
          false
        end
      | Ordering_Greater =>
        match other with
        | Ordering_Greater =>
          true
        | _ =>
          false
        end
      end);
  }.

Class t_PartialOrd (v_Self : Type) (v_Rhs : Type) `{t_PartialEq (v_Self) (v_Rhs)} : Type :=
  {
    PartialOrd_f_partial_cmp : v_Self -> v_Rhs -> t_Option ((t_Ordering));
    PartialOrd_f_lt : v_Self -> v_Rhs -> bool;
    PartialOrd_f_le : v_Self -> v_Rhs -> bool;
    PartialOrd_f_gt : v_Self -> v_Rhs -> bool;
    PartialOrd_f_ge : v_Self -> v_Rhs -> bool;
  }.
Arguments t_PartialOrd (_) (_) {_}.