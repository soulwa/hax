let make_metadata rejection_phase =
  Phase_utils.Metadata.make (Diagnostics.Phase.Reject rejection_phase)

module Arbitrary_lhs (FA : Features.T) = struct
  module FB = struct
    include FA
    include Features.Off.Arbitrary_lhs
  end

  include
    Feature_gate.Make (FA) (FB)
      (struct
        module A = FA
        module B = FB
        include Feature_gate.DefaultSubtype

        let arbitrary_lhs = reject
        let metadata = make_metadata ArbitraryLhs
      end)
end

module _ (FA : Features.T) : Phase_utils.PHASE = Arbitrary_lhs (FA)

module Continue (FA : Features.T) = struct
  module FB = struct
    include FA
    include Features.Off.Continue
  end

  include
    Feature_gate.Make (FA) (FB)
      (struct
        module A = FA
        module B = FB
        include Feature_gate.DefaultSubtype

        let continue = reject
        let metadata = make_metadata Continue
      end)
end

module _ (FA : Features.T) : Phase_utils.PHASE = Continue (FA)

module RawOrMutPointer (FA : Features.T) = struct
  module FB = struct
    include FA
    include Features.Off.Raw_pointer
    include Features.Off.Mutable_pointer
  end

  include
    Feature_gate.Make (FA) (FB)
      (struct
        module A = FA
        module B = FB
        include Feature_gate.DefaultSubtype

        let mutable_pointer = reject
        let raw_pointer = reject
        let metadata = make_metadata RawOrMutPointer
      end)
end

module _ (FA : Features.T) : Phase_utils.PHASE = RawOrMutPointer (FA)

module EarlyExit (FA : Features.T) = struct
  module FB = struct
    include FA
    include Features.Off.Early_exit
  end

  include
    Feature_gate.Make (FA) (FB)
      (struct
        module A = FA
        module B = FB
        include Feature_gate.DefaultSubtype

        let early_exit = reject
        let metadata = make_metadata EarlyExit
      end)
end