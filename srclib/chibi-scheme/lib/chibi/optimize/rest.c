/*  rest.c -- low-level utilities for VM rest optimization    */
/*  Copyright (c) 2011 Alex Shinn.  All rights reserved.      */
/*  BSD-style license: http://synthcode.com/license.txt       */

#include <chibi/eval.h>

static sexp sexp_num_parameters (sexp ctx sexp_api_params(self, n)) {
  return sexp_stack_data(sexp_context_stack(ctx))[sexp_context_last_fp(ctx)];
}

struct sexp_opcode_struct local_ref_op =
  {SEXP_OPC_GENERIC, SEXP_OP_LOCAL_REF, 1, 8, 0, "local-ref", SEXP_VOID,
   NULL, NULL, sexp_make_fixnum(SEXP_OBJECT), sexp_make_fixnum(SEXP_FIXNUM),
   0, 0, NULL};

static sexp sexp_copy_opcode (sexp ctx, struct sexp_opcode_struct *op) {
  sexp res = sexp_alloc_type(ctx, opcode, SEXP_OPCODE);
  memcpy(&(res->value), op, sizeof(op[0]));
  return res;
}

sexp sexp_init_library (sexp ctx sexp_api_params(self, n), sexp env) {
  sexp_gc_var2(name, op);
  sexp_gc_preserve2(ctx, name, op);
  sexp_define_foreign(ctx, env, "num-parameters", 0, sexp_num_parameters);
  op = sexp_copy_opcode(ctx, &local_ref_op);
  name = sexp_intern(ctx, sexp_opcode_name(op), -1);
  sexp_env_define(ctx, env, name, op);
  sexp_gc_release2(ctx);
  return SEXP_VOID;
}
