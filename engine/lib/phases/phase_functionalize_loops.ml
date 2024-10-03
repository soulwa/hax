open! Prelude

module%inlined_contents Make
    (F : Features.T
           with type continue = Features.Off.continue
            and type early_exit = Features.Off.early_exit
            and type break = Features.Off.break) =
struct
  open Ast
  module FA = F

  module FB = struct
    include F
    include Features.Off.Loop
    include Features.Off.For_loop
    include Features.Off.While_loop
    include Features.Off.For_index_loop
    include Features.Off.State_passing_loop
    include Features.Off.Continue
    include Features.Off.Early_exit
    include Features.Off.Break
  end

  include
    Phase_utils.MakeBase (F) (FB)
      (struct
        let phase_id = Diagnostics.Phase.FunctionalizeLoops
      end)

  module Implem : ImplemT.T = struct
    let metadata = metadata

    module UA = Ast_utils.Make (F)
    module UB = Ast_utils.Make (FB)
    module Visitors = Ast_visitors.Make (F)

    module S = struct
      include Features.SUBTYPE.Id
    end

    type body_and_invariant = {
      body : B.expr;
      invariant : (B.pat * B.expr) option;
    }

    let has_cf =
      object (_self)
        inherit [_] Visitors.reduce as super
        method zero = false
        method plus = ( || )

        method! visit_expr' () e =
          match e with
          | Return _ | Break _ | Continue _ -> true
          | _ -> super#visit_expr' () e
      end

    let extract_loop_invariant (body : B.expr) : body_and_invariant =
      match body.e with
      | Let
          {
            monadic = None;
            lhs = { p = PWild; _ };
            rhs =
              {
                e =
                  App
                    {
                      f = { e = GlobalVar f; _ };
                      args =
                        [
                          {
                            e =
                              Closure { params = [ pat ]; body = invariant; _ };
                            _;
                          };
                        ];
                      _;
                    };
                _;
              };
            body;
          }
        when Global_ident.eq_name Hax_lib___internal_loop_invariant f ->
          { body; invariant = Some (pat, invariant) }
      | _ -> { body; invariant = None }

    type iterator =
      | Range of { start : B.expr; end_ : B.expr }
      | Slice of B.expr
      | ChunksExact of { size : B.expr; slice : B.expr }
      | Enumerate of iterator
      | StepBy of { n : B.expr; it : iterator }
    [@@deriving show]

    let rec as_iterator (e : B.expr) : iterator option =
      match e.e with
      | Construct
          {
            constructor = `Concrete range_ctor;
            is_record = true;
            is_struct = true;
            fields =
              [ (`Concrete start_field, start); (`Concrete end_field, end_) ];
            base = None;
          }
        when Concrete_ident.eq_name Core__ops__range__Range__start start_field
             && Concrete_ident.eq_name Core__ops__range__Range range_ctor
             && Concrete_ident.eq_name Core__ops__range__Range__end end_field ->
          Some (Range { start; end_ })
      | _ -> meth_as_iterator e

    and meth_as_iterator (e : B.expr) : iterator option =
      let* f, args =
        match e.e with
        | App { f = { e = GlobalVar f; _ }; args; _ } -> Some (f, args)
        | _ -> None
      in
      let f_eq n = Global_ident.eq_name n f in
      let one_arg () = match args with [ x ] -> Some x | _ -> None in
      let two_args () = match args with [ x; y ] -> Some (x, y) | _ -> None in
      if f_eq Core__iter__traits__iterator__Iterator__step_by then
        let* it, n = two_args () in
        let* it = as_iterator it in
        Some (StepBy { n; it })
      else if
        f_eq Core__iter__traits__collect__IntoIterator__into_iter
        || f_eq Core__slice__Impl__iter
      then
        let* iterable = one_arg () in
        match iterable.typ with
        | TSlice _ | TArray _ -> Some (Slice iterable)
        | _ -> as_iterator iterable
      else if f_eq Core__iter__traits__iterator__Iterator__enumerate then
        let* iterable = one_arg () in
        let* iterator = as_iterator iterable in
        Some (Enumerate iterator)
      else if f_eq Core__slice__Impl__chunks_exact then
        let* slice, size = two_args () in
        Some (ChunksExact { size; slice })
      else None

    let fn_args_of_iterator (has_cf : bool) (has_return : bool) (it : iterator)
        : (Concrete_ident.name * B.expr list * B.ty) option =
      let open Concrete_ident_generated in
      let usize = B.TInt { size = SSize; signedness = Unsigned } in
      match it with
      | Enumerate (ChunksExact { size; slice }) ->
          let fold_op =
            if has_return then
              Rust_primitives__hax__folds__fold_enumerated_chunked_slice_return
            else if has_cf then
              Rust_primitives__hax__folds__fold_enumerated_chunked_slice_cf
            else Rust_primitives__hax__folds__fold_enumerated_chunked_slice
          in
          Some (fold_op, [ size; slice ], usize)
      | Enumerate (Slice slice) ->
          let fold_op =
            if has_return then
              Rust_primitives__hax__folds__fold_enumerated_slice_return
            else if has_cf then
              Rust_primitives__hax__folds__fold_enumerated_slice_cf
            else Rust_primitives__hax__folds__fold_enumerated_slice
          in
          Some (fold_op, [ slice ], usize)
      | StepBy { n; it = Range { start; end_ } } ->
          let fold_op =
            if has_return then
              Rust_primitives__hax__folds__fold_range_step_by_return
            else if has_cf then
              Rust_primitives__hax__folds__fold_range_step_by_cf
            else Rust_primitives__hax__folds__fold_range_step_by
          in
          Some (fold_op, [ start; end_; n ], start.typ)
      | Range { start; end_ } ->
          let fold_op =
            if has_return then Rust_primitives__hax__folds__fold_range_return
            else if has_cf then Rust_primitives__hax__folds__fold_range_cf
            else Rust_primitives__hax__folds__fold_range
          in
          Some (fold_op, [ start; end_ ], start.typ)
      | _ -> None

    [%%inline_defs dmutability + dsafety_kind]

    let rec dexpr_unwrapped (expr : A.expr) : B.expr =
      let span = expr.span in
      let module M = UB.M in
      let module MS = (val M.make span) in
      match expr.e with
      | Loop
          {
            body;
            kind = ForLoop { it; pat; has_return; _ };
            state = Some { init; bpat; _ };
            control_flow;
            _;
          } ->
          let body = dexpr body in
          let { body; invariant } = extract_loop_invariant body in
          let it = dexpr it in
          let pat = dpat pat in
          let bpat = dpat bpat in
          let fn : B.expr = UB.make_closure [ bpat; pat ] body body.span in
          let init = dexpr init in
          let f, kind, args =
            match
              as_iterator it
              |> Option.bind ~f:(fn_args_of_iterator control_flow has_return)
            with
            | Some (f, args, typ) ->
                (* TODO what happens if there is control flow? *)
                let invariant : B.expr =
                  let default =
                    let pat = MS.pat_PWild ~typ in
                    (pat, MS.expr_Literal ~typ:TBool (Bool true))
                  in
                  let pat, invariant = Option.value ~default invariant in
                  UB.make_closure [ bpat; pat ] invariant invariant.span
                in
                (f, Concrete_ident.Kind.Value, args @ [ invariant; init; fn ])
            | None ->
                let fold : Concrete_ident.name =
                  if has_return then Rust_primitives__hax__folds__fold_return
                  else if control_flow then Rust_primitives__hax__folds__fold_cf
                  else Core__iter__traits__iterator__Iterator__fold
                in
                (fold, AssociatedItem Value, [ it; init; fn ])
          in
          UB.call ~kind f args span (dty span expr.typ)
      | Loop
          {
            body;
            kind = WhileLoop { condition; has_return; _ };
            state = Some { init; bpat; _ };
            control_flow;
            _;
          } ->
          let body = dexpr body in
          let condition = dexpr condition in
          let bpat = dpat bpat in
          let init = dexpr init in
          let condition : B.expr =
            M.expr_Closure ~params:[ bpat ] ~body:condition ~captures:[]
              ~span:condition.span
              ~typ:(TArrow ([ bpat.typ ], condition.typ))
          in
          let body : B.expr =
            M.expr_Closure ~params:[ bpat ] ~body ~captures:[]
              ~typ:(TArrow ([ bpat.typ ], body.typ))
              ~span:body.span
          in
          let fold_operator : Concrete_ident.name =
            if has_return then Rust_primitives__hax__while_loop_return
            else if control_flow then Rust_primitives__hax__while_loop_cf
            else Rust_primitives__hax__while_loop
          in
          UB.call ~kind:(AssociatedItem Value) fold_operator
            [ condition; init; body ] span (dty span expr.typ)
      | Loop { state = None; _ } ->
          Error.unimplemented ~issue_id:405 ~details:"Loop without mutation"
            span
      | Loop _ ->
          Error.unimplemented ~issue_id:933 ~details:"Unhandled loop kind" span
      | [%inline_arms "dexpr'.*" - Loop - Break - Continue - Return] ->
          map (fun e -> B.{ e; typ = dty expr.span expr.typ; span = expr.span })
      | _ -> .
      [@@inline_ands bindings_of dexpr - dexpr' - dloop_kind - dloop_state]

    [%%inline_defs "Item.*"]
  end

  include Implem
end
[@@add "subtype.ml"]
