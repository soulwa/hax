use crate::prelude::*;

#[tracing::instrument(skip(s))]
pub(crate) fn arrow_of_sig<'tcx, S: BaseState<'tcx>>(
    sig: &rustc_middle::ty::PolyFnSig<'tcx>,
    s: &S,
) -> Ty {
    Ty::Arrow(Box::new(sig.sinto(s)))
}

#[tracing::instrument(skip(s))]
pub(crate) fn get_variant_information<'s, S: BaseState<'s>>(
    adt_def: &rustc_middle::ty::AdtDef<'s>,
    variant: &rustc_hir::def_id::DefId,
    s: &S,
) -> VariantInformations {
    s_assert!(s, !adt_def.is_enum());
    fn is_record<'s, I: std::iter::Iterator<Item = &'s rustc_middle::ty::FieldDef> + Clone>(
        it: I,
    ) -> bool {
        it.clone()
            .any(|field| !field.name.to_ident_string().parse::<u64>().is_ok())
    }
    let (variant_index, variant_def) = adt_def
        .variants()
        .iter_enumerated()
        .find(|(_, v)| v.def_id == variant.clone())
        .s_unwrap(s);
    let constructs_type: DefId = adt_def.did().sinto(s);
    VariantInformations {
        typ: constructs_type.clone(),
        variant: variant.sinto(s),
        variant_index: variant_index.into(),

        typ_is_record: adt_def.is_struct() && is_record(adt_def.all_fields()),
        variant_is_record: is_record(variant_def.fields.iter()),
        typ_is_struct: adt_def.is_struct(),

        type_namespace: DefId {
            path: match constructs_type.path.as_slice() {
                [init @ .., _] => init.to_vec(),
                _ => {
                    let span = s.base().tcx.def_span(variant);
                    span_fatal!(
                        s,
                        span,
                        "Type {:#?} appears to have no path",
                        constructs_type
                    )
                }
            },
            ..constructs_type.clone()
        },
    }
}

#[derive(Debug)]
pub enum ReadSpanErr {
    NotRealFileName(String),
    WhileReading(std::io::Error),
    NotEnoughLines { span: Span },
}
impl std::convert::From<std::io::Error> for ReadSpanErr {
    fn from(value: std::io::Error) -> Self {
        ReadSpanErr::WhileReading(value)
    }
}

#[tracing::instrument]
pub(crate) fn read_span_from_file(span: &Span) -> Result<String, ReadSpanErr> {
    use ReadSpanErr::*;
    let realpath = (match span.filename.clone() {
        FileName::Real(RealFileName::LocalPath(path)) => Ok(path),
        _ => Err(NotRealFileName(format!("{:#?}", span.filename))),
    })?;
    use std::fs::File;
    use std::io::{prelude::*, BufReader};
    let file = File::open(realpath)?;
    let reader = BufReader::new(file);
    let lines = reader
        .lines()
        .skip(span.lo.line - 1)
        .take(span.hi.line - span.lo.line + 1)
        .collect::<Result<Vec<_>, _>>()?;

    match lines.as_slice() {
        [] => Err(NotEnoughLines { span: span.clone() }),
        [line] => Ok(line
            .chars()
            .enumerate()
            .filter(|(i, _)| *i >= span.lo.col && *i < span.hi.col)
            .map(|(_, c)| c)
            .collect()),
        [first, middle @ .., last] => {
            let first = first.chars().skip(span.lo.col).collect();
            let last = last.chars().take(span.hi.col).collect();
            Ok(std::iter::once(first)
                .chain(middle.into_iter().cloned())
                .chain(std::iter::once(last))
                .collect::<Vec<String>>()
                .join("\n"))
        }
    }
}

#[tracing::instrument(skip(sess))]
pub fn translate_span(span: rustc_span::Span, sess: &rustc_session::Session) -> Span {
    let smap: &rustc_span::source_map::SourceMap = sess.parse_sess.source_map();
    let filename = smap.span_to_filename(span);

    let lo = smap.lookup_char_pos(span.lo());
    let hi = smap.lookup_char_pos(span.hi());

    Span {
        lo: lo.into(),
        hi: hi.into(),
        filename: filename.sinto(&()),
    }
}

#[tracing::instrument(skip(s))]
pub(crate) fn get_param_env<'tcx, S: BaseState<'tcx>>(s: &S) -> rustc_middle::ty::ParamEnv<'tcx> {
    match s.base().opt_def_id {
        Some(id) => s.base().tcx.param_env(id),
        None => rustc_middle::ty::ParamEnv::empty(),
    }
}

#[tracing::instrument(skip(s))]
#[allow(dead_code)]
#[allow(unused)]
pub(crate) fn _resolve_trait<'tcx, S: BaseState<'tcx>>(
    trait_ref: rustc_middle::ty::TraitRef<'tcx>,
    s: &S,
) {
    let tcx = s.base().tcx;
    let param_env = get_param_env(s);
    use rustc_middle::ty::Binder;
    let binder: Binder<'tcx, _> = Binder::dummy(trait_ref);
    use rustc_infer::infer::TyCtxtInferExt;
    use rustc_infer::traits;
    use rustc_middle::ty::{ParamEnv, ParamEnvAnd};
    use rustc_trait_selection::infer::InferCtxtBuilderExt;
    use rustc_trait_selection::traits::SelectionContext;
    let inter_ctxt = tcx.infer_ctxt().ignoring_regions().build();
    let mut selection_ctxt = SelectionContext::new(&inter_ctxt);
    use std::collections::VecDeque;
    let mut queue = VecDeque::new();
    let obligation = traits::Obligation::new(
        tcx,
        traits::ObligationCause::dummy(),
        param_env,
        rustc_middle::ty::Binder::dummy(trait_ref),
    );
    use rustc_middle::traits::ImplSource;
    queue.push_back(obligation);
    loop {
        match queue.pop_front() {
            Some(obligation) => {
                let impl_source = selection_ctxt.select(&obligation).unwrap().unwrap();
                println!("impl_source={:#?}", impl_source);
                let nested = impl_source.clone().nested_obligations();
                for subobligation in nested {
                    let bound_predicate = subobligation.predicate.kind();
                    match bound_predicate.skip_binder() {
                        rustc_middle::ty::PredicateKind::Clause(
                            rustc_middle::ty::Clause::Trait(trait_pred),
                        ) => {
                            let trait_pred = bound_predicate.rebind(trait_pred);
                            let subobligation = subobligation.with(tcx, trait_pred);
                            queue.push_back(subobligation);
                        }
                        _ => (),
                    }
                }
            }
            None => break,
        }
    }
    // let impl_source = selection_ctxt.select(&obligation).unwrap().unwrap();
    // let nested = impl_source.clone().nested_obligations();
}

#[tracing::instrument]
pub fn argument_span_of_mac_call(mac_call: &rustc_ast::ast::MacCall) -> rustc_span::Span {
    (*mac_call.args).dspan.entire()
}
#[tracing::instrument(skip(state))]
pub(crate) fn raw_macro_invocation_of_span<'t, S: BaseState<'t>>(
    span: rustc_span::Span,
    state: &S,
) -> Option<(DefId, rustc_span::hygiene::ExpnData)> {
    let opts: Rc<hax_frontend_exporter_options::Options> = state.base().options;
    let macro_calls: crate::state::MacroCalls = state.base().macro_infos;

    let sess = state.base().tcx.sess;

    span.macro_backtrace().find_map(|expn_data| {
        let expn_data_ret = expn_data.clone();
        let call_site = translate_span(expn_data.call_site, sess);
        match (expn_data.kind, expn_data.macro_def_id) {
            (rustc_span::hygiene::ExpnKind::Macro(_, _), Some(mac_def_id))
                if macro_calls.keys().any(|span| span.clone() == call_site) =>
            {
                let macro_ident: DefId = mac_def_id.sinto(state);
                let path = Path::from(macro_ident.clone());
                if opts
                    .inline_macro_calls
                    .iter()
                    .any(|pattern| pattern.matches(&path))
                {
                    Some((macro_ident, expn_data_ret))
                } else {
                    None
                }
            }
            _ => None,
        }
    })
}

#[tracing::instrument(skip(state))]
pub(crate) fn macro_invocation_of_raw_mac_invocation<'t, S: BaseState<'t>>(
    macro_ident: &DefId,
    expn_data: &rustc_span::hygiene::ExpnData,
    state: &S,
) -> MacroInvokation {
    let macro_infos = state.base().macro_infos;
    let mac_call_span = macro_infos
        .get(&translate_span(expn_data.call_site, state.base().tcx.sess))
        .unwrap_or_else(|| fatal!(state, "{:#?}", expn_data.call_site));
    MacroInvokation {
        macro_ident: macro_ident.clone(),
        argument: read_span_from_file(mac_call_span).s_unwrap(state),
        span: expn_data.call_site.sinto(state),
    }
}

#[tracing::instrument(skip(state))]
pub(crate) fn macro_invocation_of_span<'t, S: BaseState<'t>>(
    span: rustc_span::Span,
    state: &S,
) -> Option<MacroInvokation> {
    let (macro_ident, expn_data) = raw_macro_invocation_of_span(span, state)?;
    Some(macro_invocation_of_raw_mac_invocation(
        &macro_ident,
        &expn_data,
        state,
    ))
}

#[tracing::instrument(skip(s))]
pub(crate) fn attribute_from_scope<'tcx, S: ExprState<'tcx>>(
    s: &S,
    scope: &rustc_middle::middle::region::Scope,
) -> (Option<rustc_hir::hir_id::HirId>, Vec<Attribute>) {
    let owner = s.owner_id();
    let tcx = s.base().tcx;
    let scope_tree = tcx.region_scope_tree(owner.to_def_id());
    let hir_id = scope.hir_id(scope_tree);
    let tcx = s.base().tcx;
    let map = tcx.hir();
    let attributes = hir_id
        .map(|hir_id| map.attrs(hir_id).sinto(s))
        .unwrap_or(vec![]);
    (hir_id, attributes)
}

use itertools::Itertools;

pub fn inline_macro_invocations<'t, S: BaseState<'t>, Body: IsBody>(
    ids: impl Iterator<Item = rustc_hir::ItemId>,
    s: &S,
) -> Vec<Item<Body>> {
    let tcx: rustc_middle::ty::TyCtxt = s.base().tcx;

    struct SpanEq(Option<(DefId, rustc_span::hygiene::ExpnData)>);
    impl core::cmp::PartialEq for SpanEq {
        fn eq(&self, other: &SpanEq) -> bool {
            let project = |x: &SpanEq| x.0.clone().map(|x| x.1.call_site);
            project(self) == project(other)
        }
    }

    ids.map(|id| tcx.hir().item(id))
        .group_by(|item| SpanEq(raw_macro_invocation_of_span(item.span, s)))
        .into_iter()
        .map(|(mac, items)| match mac.0 {
            Some((macro_ident, expn_data)) => {
                let owner_id = items.into_iter().map(|x| x.owner_id).next().s_unwrap(s);
                // owner_id.reduce()
                let invocation =
                    macro_invocation_of_raw_mac_invocation(&macro_ident, &expn_data, s);
                let span = expn_data.call_site.sinto(s);
                vec![Item {
                    def_id: None,
                    owner_id: owner_id.sinto(s),
                    kind: ItemKind::MacroInvokation(invocation),
                    span,
                    vis_span: rustc_span::DUMMY_SP.sinto(s),
                    attributes: vec![],
                    expn_backtrace: vec![],
                }]
            }
            _ => items.map(|item| item.sinto(s)).collect(),
        })
        .flatten()
        .collect()
}
