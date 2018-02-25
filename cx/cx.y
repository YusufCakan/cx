%{
	package main
	import (
		// "strings"
		// "fmt"
		// "os"
		// "time"

		// "github.com/skycoin/cx/cx/cx0"
		"github.com/skycoin/skycoin/src/cipher/encoder"
		. "github.com/skycoin/cx/src/base"
	)

	var prgrm = MakeProgram(256, 256, 256)
	// var data Data
	var dataOffset int

	var lineNo int = 0
	var webMode bool = false
	var baseOutput bool = false
	var replMode bool = false
	var helpMode bool = false
	var compileMode bool = false
	var replTargetFn string = ""
	var replTargetStrct string = ""
	var replTargetMod string = ""
	// var dStack bool = false
	var inREPL bool = false
	// var inFn bool = false
	// var tag string = ""
	// var asmNL = "\n"
	var fileName string

	var sysInitExprs []*CXExpression

	// used for selection_statement to layout its outputs
	type selectStatement struct {
		Condition []*CXExpression
		Then []*CXExpression
		Else []*CXExpression
	}

	// Primary expressions (literals) are saved in the MEM_DATA segment at compile-time
	// This function writes those bytes to prgrm.Data
	func WritePrimary (typ int, byts []byte) []*CXExpression {
		if pkg, err := prgrm.GetCurrentPackage(); err == nil {
			arg := MakeArgument(typ)
			arg.MemoryType = MEM_DATA
			arg.Offset = dataOffset
			arg.Package = pkg
			arg.Program = prgrm
			size := len(byts)
			arg.Size = size
			arg.TotalSize = size
			arg.PointeeSize = size
			dataOffset += size
			prgrm.Data = append(prgrm.Data, Data(byts)...)
			expr := MakeExpression(nil)
			expr.Package = pkg
			expr.Outputs = append(expr.Outputs, arg)
			return []*CXExpression{expr}
		} else {
			panic(err)
		}
	}

	func TotalLength (lengths []int) int {
		var total int = 1
		for _, i := range lengths {
			total *= i
		}
		return total
	}

	func IterationExpressions (init []*CXExpression, cond []*CXExpression, incr []*CXExpression, statements []*CXExpression) []*CXExpression {
		jmpFn := Natives[OP_JMP]

		pkg, err := prgrm.GetCurrentPackage()
		if err != nil {
			panic(err)
		}
		
		upExpr := MakeExpression(jmpFn)
		upExpr.Package = pkg
		
		trueArg := WritePrimary(TYPE_BOOL, encoder.Serialize(true))

		upLines := (len(statements) + len(incr) + len(cond) + 2) * -1
		downLines := 0
		
		upExpr.AddInput(trueArg[0].Outputs[0])
		upExpr.ThenLines = upLines
		upExpr.ElseLines = downLines
		
		downExpr := MakeExpression(jmpFn)
		downExpr.Package = pkg

		if len(cond[len(cond) - 1].Outputs) < 1 {
			predicate := MakeParameter(MakeGenSym(LOCAL_PREFIX), cond[len(cond) - 1].Operator.Outputs[0].Type)
			predicate.Package = pkg
			cond[len(cond) - 1].AddOutput(predicate)
			downExpr.AddInput(predicate)
		} else {
			predicate := cond[len(cond) - 1].Outputs[0]
			predicate.Package = pkg
			downExpr.AddInput(predicate)
		}

		thenLines := 0
		elseLines := len(incr) + len(statements) + 1
		
		downExpr.ThenLines = thenLines
		downExpr.ElseLines = elseLines
		
		exprs := init
		exprs = append(exprs, cond...)
		exprs = append(exprs, downExpr)
		exprs = append(exprs, statements...)
		exprs = append(exprs, incr...)
		exprs = append(exprs, upExpr)
		
		return exprs
	}

	func StructLiteralAssignment (to []*CXExpression, from []*CXExpression) []*CXExpression {
		for _, f := range from {
			f.Outputs[0].Name = to[0].Outputs[0].Name
			f.Outputs[0].DereferenceOperations = append(f.Outputs[0].DereferenceOperations, DEREF_FIELD)
		}
		
		return from
	}

	func Assignment (to []*CXExpression, from []*CXExpression) []*CXExpression {
		idx := len(from) - 1

		if from[idx].Operator == nil {
			from[idx].Operator = Natives[OP_IDENTITY]
			to[0].Outputs[0].Size = from[idx].Outputs[0].Size
			to[0].Outputs[0].Lengths = from[idx].Outputs[0].Lengths
			
			from[idx].Inputs = from[idx].Outputs
			from[idx].Outputs = to[len(to) - 1].Outputs

			return append(to[:len(to) - 1], from...)
			// return append(to, from...)
		} else {
			if from[idx].Operator.IsNative {
				for i, out := range from[idx].Operator.Outputs {
					to[0].Outputs[i].Size = Natives[from[idx].Operator.OpCode].Outputs[i].Size
					to[0].Outputs[i].Lengths = out.Lengths
				}
			} else {
				for i, out := range from[idx].Operator.Outputs {
					to[0].Outputs[i].Size = out.Size
					to[0].Outputs[i].Lengths = out.Lengths
				}
			}
			
			from[idx].Outputs = to[0].Outputs

			return append(to[:len(to) - 1], from...)
			// return append(to, from...)
		}
	}

	func SelectionExpressions (condExprs []*CXExpression, thenExprs []*CXExpression, elseExprs []*CXExpression) []*CXExpression {
		jmpFn := Natives[OP_JMP]
		pkg, err := prgrm.GetCurrentPackage()
		if err != nil {
			panic(err)
		}
		ifExpr := MakeExpression(jmpFn)
		ifExpr.Package = pkg

		var predicate *CXArgument
		if condExprs[len(condExprs) - 1].Operator == nil {
			// then it's a literal
			predicate = condExprs[len(condExprs) - 1].Outputs[0]
		} else {
			// then it's an expression
			predicate = MakeParameter(MakeGenSym(LOCAL_PREFIX), condExprs[len(condExprs) - 1].Operator.Outputs[0].Type)
			condExprs[len(condExprs) - 1].Outputs = append(condExprs[len(condExprs) - 1].Outputs, predicate)
		}
		predicate.Package = pkg

		ifExpr.AddInput(predicate)

		thenLines := 0
		elseLines := len(thenExprs) + 1

		ifExpr.ThenLines = thenLines
		ifExpr.ElseLines = elseLines

		skipExpr := MakeExpression(jmpFn)
		skipExpr.Package = pkg

		trueArg := WritePrimary(TYPE_BOOL, encoder.Serialize(true))
		skipLines := len(elseExprs)

		skipExpr.AddInput(trueArg[0].Outputs[0])
		skipExpr.ThenLines = skipLines
		skipExpr.ElseLines = 0

		var exprs []*CXExpression
		if condExprs[len(condExprs) - 1].Operator != nil {
			exprs = append(exprs, condExprs...)
		}
		exprs = append(exprs, ifExpr)
		exprs = append(exprs, thenExprs...)
		exprs = append(exprs, skipExpr)
		exprs = append(exprs, elseExprs...)
		
		return exprs
	}

	func GiveOffset (symbols *map[string]*CXArgument, sym *CXArgument, offset *int, shouldExist bool) {
		if sym.Name != "" {
			if arg, found := (*symbols)[sym.Package.Name + "." + sym.Name]; !found {
				if glbl, err := sym.Package.GetGlobal(sym.Name); err == nil {
					sym.Offset = glbl.Offset
					sym.MemoryType = glbl.MemoryType
					sym.Size = glbl.Size
					sym.TotalSize = glbl.TotalSize
					sym.Package = glbl.Package
					sym.Program = glbl.Program
					// sym.IsReference = glbl.IsReference
					(*symbols)[sym.Package.Name + "." + sym.Name] = sym
					return
				}
				if shouldExist {
					// it should exist. error
					panic("identifier '" + sym.Name + "' does not exist")
				}
				
				sym.Offset = *offset
				(*symbols)[sym.Package.Name + "." + sym.Name] = sym
				*offset += sym.TotalSize

				if sym.IsPointer {
					pointer := sym
					for c := 0; c < sym.IndirectionLevels - 1; c++ {
						pointer = pointer.Pointee
						pointer.Offset = *offset
						*offset += pointer.TotalSize
					}
				}
			} else {
				var isFieldPointer bool
				if len(sym.Fields) > 0 {
					var found bool

					strct := arg.CustomType
					for _, nameFld := range sym.Fields {
						for _, fld := range strct.Fields {
							if nameFld.Name == fld.Name {
								if fld.IsPointer {
									sym.IsPointer = true
									// sym.IndirectionLevels = fld.IndirectionLevels
									isFieldPointer = true
								}
								found = true
								if fld.CustomType != nil {
									strct = fld.CustomType
								}
								break
							}
						}
						if !found {
							panic("field '" + nameFld.Name + "' not found")
						}
					}
				}
				
				if sym.DereferenceLevels > 0 {
					if arg.IndirectionLevels >= sym.DereferenceLevels || isFieldPointer { // ||
						// 	sym.IndirectionLevels >= sym.DereferenceLevels
						// {
						pointer := arg

						for c := 0; c < sym.DereferenceLevels - 1; c++ {
							pointer = pointer.Pointee
						}

						sym.Offset = pointer.Offset
						sym.IndirectionLevels = pointer.IndirectionLevels
						sym.IsPointer = pointer.IsPointer
					} else {
						panic("invalid indirect of " + sym.Name)
					}
				} else {
					sym.Offset = arg.Offset
					sym.IsPointer = arg.IsPointer
					sym.IndirectionLevels = arg.IndirectionLevels
				}

				//if sym.IsStruct {
				// checking if it's accessing fields
				if len(sym.Fields) > 0 {
					var found bool

					strct := arg.CustomType
					for _, nameFld := range sym.Fields {
						for _, fld := range strct.Fields {
							if nameFld.Name == fld.Name {
								nameFld.Lengths = fld.Lengths
								nameFld.Size = fld.Size
								nameFld.TotalSize = fld.TotalSize
								nameFld.DereferenceLevels = sym.DereferenceLevels
								nameFld.IsPointer = fld.IsPointer
								found = true
								if fld.CustomType != nil {
									strct = fld.CustomType
								}
								break
							}
							
							nameFld.Offset += fld.TotalSize
						}
						if !found {
							panic("field '" + nameFld.Name + "' not found")
						}
					}
				}
				//}

				// sym.IsPointer = arg.IsPointer
				sym.Type = arg.Type
				sym.Pointee = arg.Pointee
				sym.Lengths = arg.Lengths
				sym.PointeeSize = arg.PointeeSize
				sym.Package = arg.Package
				sym.Program = arg.Program
				sym.MemoryType = arg.MemoryType
				if sym.IsReference && !arg.IsStruct {
					// sym.Size = TYPE_POINTER_SIZE
					sym.TotalSize = TYPE_POINTER_SIZE
					
					sym.Size = arg.Size
					// sym.TotalSize = arg.TotalSize
				} else {
					sym.Size = arg.Size
					sym.TotalSize = arg.TotalSize
				}

				var subTotalSize int
				if len(sym.Indexes) > 0 {
					// then we need to adjust TotalSize depending on the number of indexes
					for i, _ := range sym.Indexes {
						var subSize int = 1
						for _, len := range sym.Lengths[i+1:] {
							subSize *= len
						}
						subTotalSize += subSize * sym.Size
					}
					sym.TotalSize = sym.TotalSize - subTotalSize
				}
			}
		}
	}

	func FunctionDeclaration (fn *CXFunction, inputs []*CXArgument, outputs []*CXArgument, exprs []*CXExpression) {
		// adding inputs, outputs
		for _, inp := range inputs {
			fn.AddInput(inp)
		}
		for _, out := range outputs {
			fn.AddOutput(out)
		}

		// // getting offset to use by statements (excluding inputs, outputs and receiver)
		var offset int

		for _, expr := range exprs {
			fn.AddExpression(expr)
		}

		fn.Length = len(fn.Expressions)

		var symbols map[string]*CXArgument = make(map[string]*CXArgument, 0)
		
		for _, inp := range fn.Inputs {
			GiveOffset(&symbols, inp, &offset, false)
		}
		for _, out := range fn.Outputs {
			GiveOffset(&symbols, out, &offset, false)
		}

		for _, expr := range fn.Expressions {
			for _, inp := range expr.Inputs {
				GiveOffset(&symbols, inp, &offset, true)
				for _, idx := range inp.Indexes {
					GiveOffset(&symbols, idx, &offset, true)
				}
			}
			for _, out := range expr.Outputs {
				GiveOffset(&symbols, out, &offset, false)
				for _, idx := range out.Indexes {
					GiveOffset(&symbols, idx, &offset, true)
				}
			}
		}
		fn.Size = offset
	}

	func FunctionCall (exprs []*CXExpression, args []*CXExpression) []*CXExpression {
		expr := exprs[len(exprs) - 1]
		
		if expr.Operator == nil {
			opName := expr.Outputs[0].Name
			opPkg := expr.Outputs[0].Package
			if len(expr.Outputs[0].Fields) > 0 {
				opName = expr.Outputs[0].Fields[0].Name
				// it wasn't a field, but a method call. removing it as a field
				expr.Outputs[0].Fields = expr.Outputs[0].Fields[:len(expr.Outputs[0].Fields) - 1]
				// we remove information about the "field" (method name)
				expr.AddInput(expr.Outputs[0])
				expr.Outputs = expr.Outputs[:len(expr.Outputs) - 1]
				// expr.Inputs = expr.Inputs[:len(expr.Inputs) - 1]
				// expr.AddInput(expr.Outputs[0])
			}

			if op, err := prgrm.GetFunction(opName, opPkg.Name); err == nil {
				expr.Operator = op
			} else {
				panic(err)
			}
			
			expr.Outputs = nil
		}

		var nestedExprs []*CXExpression
		for _, inpExpr := range args {
			if inpExpr.Operator == nil {
				// then it's a literal
				expr.AddInput(inpExpr.Outputs[0])
			} else {
				// then it's a function call
				if len(inpExpr.Outputs) < 1 {
					out := MakeParameter(MakeGenSym(LOCAL_PREFIX), inpExpr.Operator.Outputs[0].Type)
					out.Size = inpExpr.Operator.Outputs[0].Size
					out.TotalSize = inpExpr.Operator.Outputs[0].Size
					out.Package = inpExpr.Package
					inpExpr.AddOutput(out)
					expr.AddInput(out)
				}
				nestedExprs = append(nestedExprs, inpExpr)
			}
		}
		
		return append(nestedExprs, exprs...)
	}
%}

%union {
	i int
	byt byte
	i32 int32
	i64 int64
	f32 float32
	f64 float64
	tok string
	bool bool
	string string
	stringA []string

	line int

	argument *CXArgument
	arguments []*CXArgument

	expression *CXExpression
	expressions []*CXExpression

	selectStatement selectStatement
	selectStatements []selectStatement

        function *CXFunction
}

%token  <byt>           BYTE_LITERAL
%token  <i32>           INT_LITERAL BOOLEAN_LITERAL
%token  <i64>           LONG_LITERAL
%token  <f32>           FLOAT_LITERAL
%token  <f64>           DOUBLE_LITERAL
%token  <tok>           FUNC OP LPAREN RPAREN LBRACE RBRACE LBRACK RBRACK IDENTIFIER
                        VAR COMMA PERIOD COMMENT STRING_LITERAL PACKAGE IF ELSE FOR TYPSTRUCT STRUCT
                        SEMICOLON NEWLINE
                        ASSIGN CASSIGN IMPORT RETURN GOTO GTHAN LTHAN EQUAL COLON NEW
                        EQUALWORD GTHANWORD LTHANWORD
                        GTHANEQ LTHANEQ UNEQUAL AND OR
                        ADD_OP SUB_OP MUL_OP DIV_OP MOD_OP REF_OP NEG_OP AFFVAR
                        PLUSPLUS MINUSMINUS REMAINDER LEFTSHIFT RIGHTSHIFT EXP
                        NOT
                        BITAND BITXOR BITOR BITCLEAR
                        PLUSEQ MINUSEQ MULTEQ DIVEQ REMAINDEREQ EXPEQ
                        LEFTSHIFTEQ RIGHTSHIFTEQ BITANDEQ BITXOREQ BITOREQ

                        DEC_OP INC_OP PTR_OP LEFT_OP RIGHT_OP
                        GE_OP LE_OP EQ_OP NE_OP AND_OP OR_OP
                        ADD_ASSIGN AND_ASSIGN LEFT_ASSIGN MOD_ASSIGN
                        MUL_ASSIGN DIV_ASSIGN OR_ASSIGN RIGHT_ASSIGN
                        SUB_ASSIGN XOR_ASSIGN
                        BOOL BYTE F32 F64
                        I8 I16 I32 I64
                        STR
                        UI8 UI16 UI32 UI64
                        UNION ENUM CONST CASE DEFAULT SWITCH BREAK CONTINUE
                        TYPE
                        
                        /* Types */
                        BASICTYPE
                        /* Selectors */
                        SPACKAGE SSTRUCT SFUNC
                        /* Removers */
                        REM DEF EXPR FIELD INPUT OUTPUT CLAUSES OBJECT OBJECTS
                        /* Stepping */
                        STEP PSTEP TSTEP
                        /* Debugging */
                        DSTACK DPROGRAM DSTATE
                        /* Affordances */
                        AFF TAG INFER VALUE
                        /* Pointers */
                        ADDR

%type   <tok>           unary_operator
%type   <i>             type_specifier
%type   <argument>      declaration_specifiers
%type   <argument>      declarator
%type   <argument>      direct_declarator
%type   <argument>      parameter_declaration
%type   <arguments>     parameter_type_list
%type   <arguments>     function_parameters
%type   <arguments>     parameter_list
%type   <arguments>     fields
%type   <arguments>     struct_fields
                                                
%type   <expressions>   assignment_expression
%type   <expressions>   constant_expression
%type   <expressions>   conditional_expression
%type   <expressions>   logical_or_expression
%type   <expressions>   logical_and_expression
%type   <expressions>   exclusive_or_expression
%type   <expressions>   inclusive_or_expression
%type   <expressions>   and_expression
%type   <expressions>   equality_expression
%type   <expressions>   relational_expression
%type   <expressions>   shift_expression
%type   <expressions>   additive_expression
%type   <expressions>   multiplicative_expression
%type   <expressions>   unary_expression
%type   <expressions>   argument_expression_list
%type   <expressions>   postfix_expression
%type   <expressions>   primary_expression
%type   <expressions>   array_literal_expression

%type   <expressions>   struct_literal_fields
%type   <selectStatement>   elseif
%type   <selectStatements>   elseif_list

%type   <expressions>   declaration
//                      %type   <expressions>   init_declarator_list
//                      %type   <expressions>   init_declarator

%type   <expressions>   initializer
%type   <expressions>   initializer_list
%type   <expressions>   designation
%type   <expressions>   designator_list
%type   <expressions>   designator

%type   <expressions>   expression
%type   <expressions>   block_item
%type   <expressions>   block_item_list
%type   <expressions>   compound_statement
%type   <expressions>   else_statement
%type   <expressions>   labeled_statement
%type   <expressions>   expression_statement
%type   <expressions>   selection_statement
%type   <expressions>   iteration_statement
%type   <expressions>   jump_statement
%type   <expressions>   statement

%type   <function>      function_header

                        // for struct literals
%right                   IDENTIFIER LBRACE
// %right                  IDENTIFIER
                        
/* %start                  translation_unit */
%%

translation_unit:
                external_declaration
        |       translation_unit external_declaration
        ;

external_declaration:
                package_declaration
        |       global_declaration
        |       function_declaration
        |       import_declaration
        |       struct_declaration
        ;

global_declaration:
                VAR declarator declaration_specifiers SEMICOLON
                {
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				if _, err := prgrm.GetGlobal($2.Name); err != nil {
					expr := WritePrimary($3.Type, make([]byte, $3.Size))
					exprOut := expr[0].Outputs[0]
					$3.Name = $2.Name
					$3.MemoryType = MEM_DATA
					$3.Offset = exprOut.Offset
					$3.Size = exprOut.Size
					$3.TotalSize = exprOut.TotalSize
					$3.Package = exprOut.Package
					pkg.AddGlobal($3)
				}
			} else {
				panic(err)
			}
                }
        |       VAR declarator declaration_specifiers ASSIGN initializer SEMICOLON
                {
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				if glbl, err := prgrm.GetGlobal($2.Name); err != nil {
					expr := WritePrimary($3.Type, make([]byte, $3.Size))
					exprOut := expr[0].Outputs[0]
					$3.Name = $2.Name
					$3.MemoryType = MEM_DATA
					$3.Offset = exprOut.Offset
					$3.Size = exprOut.Size
					$3.TotalSize = exprOut.TotalSize
					$3.Package = exprOut.Package
					pkg.AddGlobal($3)
				} else {
					if $5[len($5) - 1].Operator == nil {
						expr := MakeExpression(Natives[OP_IDENTITY])
						expr.Package = pkg
						
						$3.Name = $2.Name
						$3.MemoryType = MEM_DATA
						$3.Offset = glbl.Offset
						$3.Size = glbl.Size
						$3.TotalSize = glbl.TotalSize
						$3.Package = glbl.Package

						expr.AddOutput($3)
						expr.AddInput($5[len($5) - 1].Outputs[0])

						sysInitExprs = append(sysInitExprs, expr)
					} else {
						$3.Name = $2.Name
						$3.MemoryType = MEM_DATA
						$3.Offset = glbl.Offset
						$3.Size = glbl.Size
						$3.TotalSize = glbl.TotalSize
						$3.Package = glbl.Package

						expr := $5[len($5) - 1]
						expr.AddOutput($3)

						sysInitExprs = append(sysInitExprs, $5...)
					}
				}
			} else {
				panic(err)
			}
                }
                ;

struct_declaration:
                TYPE IDENTIFIER STRUCT struct_fields
                {
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				if _, err := prgrm.GetStruct($2, pkg.Name); err != nil {
					strct := MakeStruct($2)
					pkg.AddStruct(strct)

					var size int
					for _, fld := range $4 {
						strct.AddField(fld)
						size += fld.TotalSize
					}
					strct.Size = size
				}
			} else {
				panic(err)
			}
                }
                ;

struct_fields:
                LBRACE RBRACE SEMICOLON
                { $$ = nil }
        |       LBRACE fields RBRACE SEMICOLON
                { $$ = $2 }
        ;

fields:         parameter_declaration SEMICOLON
                {
			$$ = []*CXArgument{$1}
                }
        |       fields parameter_declaration SEMICOLON
                {
			$$ = append($1, $2)
                }
        ;

package_declaration:
                PACKAGE IDENTIFIER SEMICOLON
                {
			if pkg, err := prgrm.GetPackage($2); err != nil {
				pkg := MakePackage($2)
				prgrm.AddPackage(pkg)
			} else {
				prgrm.SelectPackage(pkg.Name)
			}
                }
                ;

import_declaration:
                IMPORT STRING_LITERAL SEMICOLON
                {
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				if _, err := pkg.GetImport($2); err != nil {
					if imp, err := prgrm.GetPackage($2); err == nil {
						pkg.AddImport(imp)
					} else {
						panic(err)
					}
				}
			} else {
				panic(err)
			}
                }
        ;

function_header:
                FUNC IDENTIFIER
                {
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				if fn, err := prgrm.GetFunction($2, pkg.Name); err == nil {
					$$ = fn
				} else {
					fn := MakeFunction($2)
					pkg.AddFunction(fn)
					$$ = fn
				}
				
			} else {
				panic(err)
			}
                }
        |       FUNC LPAREN parameter_type_list RPAREN IDENTIFIER
                {
			if len($3) > 1 {
				panic("method has multiple receivers")
			}
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				if fn, err := prgrm.GetFunction($5, pkg.Name); err == nil {
					fn.AddInput($3[0])
					$$ = fn
				} else {
					fn := MakeFunction($5)
					pkg.AddFunction(fn)
					fn.AddInput($3[0])
					$$ = fn
				}
			} else {
				panic(err)
			}
                }
        ;

function_parameters:
                LPAREN RPAREN
                { $$ = nil }
        |       LPAREN parameter_type_list RPAREN
                { $$ = $2 }
                ;

function_declaration:
                function_header function_parameters compound_statement
                {
			FunctionDeclaration($1, $2, nil, $3)
                }
        |       function_header function_parameters function_parameters compound_statement
                {
			FunctionDeclaration($1, $2, $3, $4)
                }
        ;

/* method_declaration: */
/*                 FUNC */
/*         ; */



// parameter_type_list
parameter_type_list:
                //parameter_list COMMA ELLIPSIS
		parameter_list
                ;

parameter_list:
                parameter_declaration
                {
			if $1.IsArray {
				$1.TotalSize = $1.Size * TotalLength($1.Lengths)
			} else {
				$1.TotalSize = $1.Size
			}
			$$ = []*CXArgument{$1}
                }
	|       parameter_list COMMA parameter_declaration
                {
			if $3.IsArray {
				$3.TotalSize = $3.Size * TotalLength($3.Lengths)
			} else {
				$3.TotalSize = $3.Size
			}
			lastPar := $1[len($1) - 1]
			$3.Offset = lastPar.Offset + lastPar.TotalSize
			$$ = append($1, $3)
                }
                ;

parameter_declaration:
                declarator declaration_specifiers
                {
			$2.Name = $1.Name
			$2.Package = $1.Package
			// $2.IsArray = $1.IsArray
			// input and output parameters are always in the stack
			$2.MemoryType = MEM_STACK
			$$ = $2
                }
        //                      |declaration_specifiers abstract_declarator
	/* |    declaration_specifiers */
                ;

identifier_list:
                IDENTIFIER
	|       identifier_list COMMA IDENTIFIER
                ;

declarator:     direct_declarator
                ;

direct_declarator:
                IDENTIFIER
                {
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				arg := MakeArgument(TYPE_UNDEFINED)
				arg.Name = $1
				arg.Package = pkg
				$$ = arg
			} else {
				panic(err)
			}
                }
	|       LPAREN declarator RPAREN
                { $$ = $2 }
	// |       direct_declarator '[' ']'
        //         {
	// 		$1.IsArray = true
	// 		$$ = $1
        //         }
        //	|direct_declarator '[' MUL_OP ']'
        //              	|direct_declarator '[' type_qualifier_list MUL_OP ']'
        //              	|direct_declarator '[' type_qualifier_list assignment_expression ']'
        //              	|direct_declarator '[' type_qualifier_list ']'
        //              	|direct_declarator '[' assignment_expression ']'
	// |    direct_declarator LPAREN parameter_type_list RPAREN
	// |    direct_declarator LPAREN RPAREN
	// |    direct_declarator LPAREN identifier_list RPAREN
                ;

// check
/* pointer:        /\* MUL_OP   type_qualifier_list pointer // check *\/ */
/*         /\* |       MUL_OP   type_qualifier_list // check *\/ */
/*         /\* |       MUL_OP   pointer *\/ */
/*         /\* |        *\/MUL_OP */
/*                 ; */

/* type_qualifier_list: */
/*                 type_qualifier */
/* 	|       type_qualifier_list type_qualifier */
/*                 ; */








declaration_specifiers:
                MUL_OP declaration_specifiers
                {
			if !$2.IsPointer {
				$2.IsPointer = true
				$2.PointeeSize = $2.Size
				$2.Size = TYPE_POINTER_SIZE
				$2.TotalSize = TYPE_POINTER_SIZE
				$2.IndirectionLevels++
			} else {
				pointer := $2

				for c := $2.IndirectionLevels - 1; c > 0 ; c-- {
					pointer = pointer.Pointee
					pointer.IndirectionLevels = c
					pointer.IsPointer = true
				}

				pointee := MakeArgument(pointer.Type)
				// pointee.Size = pointer.Size
				// pointee.TotalSize = pointer.TotalSize
				pointee.IsPointer = true

				$2.IndirectionLevels++

				// pointer.Type = TYPE_POINTER
				pointer.Size = TYPE_POINTER_SIZE
				pointer.TotalSize = TYPE_POINTER_SIZE
				pointer.Pointee = pointee
			}
			
			$$ = $2
                }
        |       LBRACK INT_LITERAL RBRACK declaration_specifiers
                {
			arg := $4
                        arg.IsArray = true
			arg.Lengths = append([]int{int($2)}, arg.Lengths...)
			arg.TotalSize = arg.Size * TotalLength(arg.Lengths)
			// arg.Size = GetArgSize($4.Type)
			$$ = arg
                }
        |       type_specifier
                {
			arg := MakeArgument($1)
			arg.Type = $1
			arg.Size = GetArgSize($1)
			arg.TotalSize = arg.Size
			$$ = arg
                }
        |       IDENTIFIER
                {
			// custom type in the current package
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				if strct, err := prgrm.GetStruct($1, pkg.Name); err == nil {
					arg := MakeArgument(TYPE_CUSTOM)
					arg.CustomType = strct
					arg.Size = strct.Size
					arg.TotalSize = strct.Size

					$$ = arg
				} else {
					panic("type '" + $1 + "' does not exist")
				}
			} else {
				panic(err)
			}
                }
        |       IDENTIFIER PERIOD IDENTIFIER
                {
			// custom type in an imported package
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				if imp, err := pkg.GetImport($1); err == nil {
					if strct, err := prgrm.GetStruct($3, imp.Name); err == nil {
						arg := MakeArgument(TYPE_CUSTOM)
						arg.CustomType = strct
						arg.Size = strct.Size
						arg.TotalSize = strct.Size

						$$ = arg
					} else {
						panic("type '" + $1 + "' does not exist")
					}
				} else {
					panic(err)
				}
			} else {
				panic(err)
			}
                }
		/* type_specifier declaration_specifiers */
	/* |       type_specifier */
	/* |       type_qualifier declaration_specifiers */
	/* |       type_qualifier */
                ;

type_specifier:
                BOOL
                { $$ = TYPE_BOOL }
        |       BYTE
                { $$ = TYPE_BYTE }
        |       STR
                { $$ = TYPE_STR }
        |       F32
                { $$ = TYPE_F32 }
        |       F64
                { $$ = TYPE_F64 }
        |       I8
                { $$ = TYPE_I8 }
        |       I16
                { $$ = TYPE_I16 }
        |       I32
                { $$ = TYPE_I32 }
        |       I64
                { $$ = TYPE_I64 }
        |       UI8
                { $$ = TYPE_UI8 }
        |       UI16
                { $$ = TYPE_UI16 }
        |       UI32
                { $$ = TYPE_UI32 }
        |       UI64
                { $$ = TYPE_UI64 }
	/* |       struct_or_union_specifier */
        /*         { */
        /*             $$ = "struct" */
        /*         } */
	/* |       enum_specifier */
        /*         { */
        /*             $$ = "enum" */
        /*         } */
	/* |       TYPEDEF_NAME // check */
                ;


struct_literal_fields:
                // empty
                { $$ = nil }
        |       IDENTIFIER COLON constant_expression
                {
			// expr := MakeExpression(nil)
			// expr.Inputs = append(expr.Inputs, $3)
			// $$ = []*CXExpression{}
			
			// $$ = nil

			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				arg := MakeArgument(TYPE_IDENTIFIER)
				arg.Name = $1
				arg.Package = pkg

				expr := &CXExpression{Outputs: []*CXArgument{arg}}
				expr.Package = pkg

				$$ = Assignment([]*CXExpression{expr}, $3)
				
				// $$ = []*CXExpression{expr}
			} else {
				panic(err)
			}

			
                }
        |       struct_literal_fields COMMA IDENTIFIER COLON constant_expression
                {
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				arg := MakeArgument(TYPE_IDENTIFIER)
				arg.Name = $3
				arg.Package = pkg

				expr := &CXExpression{Outputs: []*CXArgument{arg}}
				expr.Package = pkg

				$$ = append($1, Assignment([]*CXExpression{expr}, $5)...)
				
				// $$ = []*CXExpression{expr}
			} else {
				panic(err)
			}
                }
                ;

// expressions
array_literal_expression:
                LBRACK INT_LITERAL RBRACK IDENTIFIER LBRACE argument_expression_list RBRACE
                {
			$$ = $6
                }
        |       LBRACK INT_LITERAL RBRACK IDENTIFIER LBRACE RBRACE
                {
			$$ = nil
                }
        |       LBRACK INT_LITERAL RBRACK type_specifier LBRACE argument_expression_list RBRACE
                {
			$$ = $6
                }
        |       LBRACK INT_LITERAL RBRACK type_specifier LBRACE RBRACE
                {
			$$ = nil
                }
        |       LBRACK INT_LITERAL RBRACK array_literal_expression
                {
			$$ = $4
                }
        ;

primary_expression:
                IDENTIFIER
                {
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				arg := MakeArgument(TYPE_IDENTIFIER)
				arg.Name = $1
				arg.Package = pkg

				expr := &CXExpression{Outputs: []*CXArgument{arg}}
				expr.Package = pkg
				
				$$ = []*CXExpression{expr}
			} else {
				panic(err)
			}
                }
        |       IDENTIFIER LBRACE struct_literal_fields RBRACE
                {
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				if strct, err := prgrm.GetStruct($1, pkg.Name); err == nil {
					for _, expr := range $3 {
						fld := MakeArgument(TYPE_IDENTIFIER)
						fld.Name = expr.Outputs[0].Name

						expr.IsStructLiteral = true
						expr.Outputs[0].CustomType = strct
						expr.Outputs[0].Size = strct.Size
						expr.Outputs[0].TotalSize = strct.Size
						expr.Outputs[0].Name = $1
						expr.Outputs[0].Fields = append(expr.Outputs[0].Fields, fld)
						$$ = append($$, expr)
					}
				} else {
					panic("type '" + $1 + "' does not exist")
				}
			} else {
				panic(err)
			}

			// $$ = $3
                }
        |       STRING_LITERAL
                {
			$$ = WritePrimary(TYPE_STR, encoder.Serialize($1))
                }
        |       BOOLEAN_LITERAL
                {
			$$ = WritePrimary(TYPE_BOOL, encoder.Serialize($1))
                }
        |       BYTE_LITERAL
                {
			$$ = WritePrimary(TYPE_BYTE, encoder.Serialize($1))
                }
        |       INT_LITERAL
                {
			$$ = WritePrimary(TYPE_I32, encoder.Serialize($1))
                }
        |       FLOAT_LITERAL
                {
			$$ = WritePrimary(TYPE_F32, encoder.Serialize($1))
                }
        |       DOUBLE_LITERAL
                {
			$$ = WritePrimary(TYPE_F64, encoder.Serialize($1))
                }
        |       LONG_LITERAL
                {
			$$ = WritePrimary(TYPE_I64, encoder.Serialize($1))
                }
        |       LPAREN expression RPAREN
                { $$ = $2 }
        |       array_literal_expression
                {
			$$ = $1
                }
                ;

postfix_expression:
                primary_expression
	|       postfix_expression LBRACK expression RBRACK
                {
			$1[len($1) - 1].Outputs[0].IsArray = false
			pastOps := $1[len($1) - 1].Outputs[0].DereferenceOperations
			if len(pastOps) < 1 || pastOps[len(pastOps) - 1] != DEREF_ARRAY {
				// this way we avoid calling deref_array multiple times (one for each index)
				$1[len($1) - 1].Outputs[0].DereferenceOperations = append($1[len($1) - 1].Outputs[0].DereferenceOperations, DEREF_ARRAY)
			}
			

			if !$1[len($1) - 1].Outputs[0].IsDereferenceFirst {
				$1[len($1) - 1].Outputs[0].IsArrayFirst = true
			}

			if len($1[len($1) - 1].Outputs[0].Fields) > 0 {
				fld := $1[len($1) - 1].Outputs[0].Fields[len($1[len($1) - 1].Outputs[0].Fields) - 1]
				fld.Indexes = append(fld.Indexes, $3[len($3) - 1].Outputs[0])
			} else {
				if len($3[len($3) - 1].Outputs) < 1 {
					// then it's an expression (e.g. i32.add(0, 0))
					// we create a gensym for it
					idxSym := MakeParameter(MakeGenSym(LOCAL_PREFIX), $3[len($3) - 1].Operator.Outputs[0].Type)
					idxSym.Size = $3[len($3) - 1].Operator.Outputs[0].Size
					idxSym.TotalSize = $3[len($3) - 1].Operator.Outputs[0].Size
					
					idxSym.Package = $3[len($3) - 1].Package
					$3[len($3) - 1].Outputs = append($3[len($3) - 1].Outputs, idxSym)

					$1[len($1) - 1].Outputs[0].Indexes = append($1[len($1) - 1].Outputs[0].Indexes, idxSym)

					// we push the index expression
					$1 = append($3, $1...)
				} else {
					$1[len($1) - 1].Outputs[0].Indexes = append($1[len($1) - 1].Outputs[0].Indexes, $3[len($3) - 1].Outputs[0])
				}
			}
			
			expr := $1[len($1) - 1]
			if len(expr.Inputs) < 1 {
				expr.Inputs = append(expr.Inputs, $1[len($1) - 1].Outputs[0])
			}

			expr.Inputs = append(expr.Inputs, $3[len($3) - 1].Outputs[0])

			$$ = $1
                }
        |       type_specifier PERIOD IDENTIFIER
                {
			// these will always be native functions
			if opCode, ok := OpCodes[TypeNames[$1] + "." + $3]; ok {
				expr := MakeExpression(Natives[opCode])
				if pkg, err := prgrm.GetCurrentPackage(); err == nil {
					expr.Package = pkg
				} else {
					panic(err)
				}
				
				$$ = []*CXExpression{expr}
			} else {
				panic(ok)
			}
                }
	|       postfix_expression LPAREN RPAREN
                {
			if $1[len($1) - 1].Operator == nil {
				// if fn, err := prgrm.GetFunction($1[len($1) - 1].Outputs[0].Name,
				// 	$1[0].Package.Name); err == nil {
				// 	// then it's a function
				// 	// $1[0].Outputs = nil
				// 	$1[0].Operator = fn
				// } else 
				if opCode, ok := OpCodes[$1[len($1) - 1].Outputs[0].Name]; ok {
					if pkg, err := prgrm.GetCurrentPackage(); err == nil {
						$1[0].Package = pkg
					}
					$1[0].Outputs = nil
					$1[0].Operator = Natives[opCode]
				}//  else {
				// 	panic(err)
				// }
			}
			
			$1[0].Inputs = nil
			$$ = FunctionCall($1, nil)
                }
	|       postfix_expression LPAREN argument_expression_list RPAREN
                {
			if $1[len($1) - 1].Operator == nil {
				// if fn, err := prgrm.GetFunction($1[len($1) - 1].Outputs[0].Name,
				// 	$1[0].Package.Name); err == nil {
				// 	// then it's a function
				// 	// $1[0].Outputs = nil
				// 	$1[0].Operator = fn
				// } else
				if opCode, ok := OpCodes[$1[len($1) - 1].Outputs[0].Name]; ok {
					if pkg, err := prgrm.GetCurrentPackage(); err == nil {
						$1[0].Package = pkg
					}
					$1[0].Outputs = nil
					$1[0].Operator = Natives[opCode]
				}//  else {
				// 	panic(err)
				// }
			}

			$1[0].Inputs = nil
			$$ = FunctionCall($1, $3)

			// $1[0].Inputs = nil
			// $$ = FunctionCall($1, $3)
                }
	|       postfix_expression INC_OP
                {
			$$ = $1
                }
        |       postfix_expression DEC_OP
                {
			$$ = $1
                }
        |       postfix_expression PERIOD IDENTIFIER
                {
			left := $1[0].Outputs[0]
			
			if left.IsRest {
				// then it can't be a module name
				// and we propagate the property to the right expression
				// right.IsRest = true
			} else {
				left.IsRest = true
				// then left is a first (e.g first.rest) and right is a rest
				// let's check if left is a package
				if pkg, err := prgrm.GetCurrentPackage(); err == nil {
					if imp, err := pkg.GetImport(left.Name); err == nil {
						// the external property will be propagated to the following arguments
						// this way we avoid considering these arguments as module names
						left.Package = imp

						if glbl, err := imp.GetGlobal($3); err == nil {
							// then it's a global
							$1[0].Outputs[0] = glbl
						} else if fn, err := prgrm.GetFunction($3, imp.Name); err == nil {
							// then it's a function
							// $1[0].Outputs = nil
							$1[0].Operator = fn
						} else {
							panic(err)
						}
					} else {
						if code, ok := ConstCodes[$1[0].Outputs[0].Name + "." + $3]; ok {
							constant := Constants[code]
							val := WritePrimary(constant.Type, constant.Value)
							$1[0].Outputs[0] = val[0].Outputs[0]
						} else if _, ok := OpCodes[$1[0].Outputs[0].Name + "." + $3]; ok {
							// then it's a native
							// TODO: we'd be referring to the function itself, not a function call
							// (functions as first-class objects)
							$1[0].Outputs[0].Name = $1[0].Outputs[0].Name + "." + $3
						} else {
							// then it's a struct
							left.IsStruct = true
							left.DereferenceOperations = append(left.DereferenceOperations, DEREF_FIELD)
							fld := MakeArgument(TYPE_IDENTIFIER)
							fld.Name = $3
							left.Fields = append(left.Fields, fld)
						}
					}
				} else {
					panic(err)
				}
			}
                }
                ;

argument_expression_list:
                assignment_expression
	|       argument_expression_list COMMA assignment_expression
                {
			$$ = append($1, $3...)
                }
                ;

unary_expression:
                postfix_expression
	|       INC_OP unary_expression
                { $$ = $2 }
	|       DEC_OP unary_expression
                { $$ = $2 }
	|       unary_operator unary_expression // check
                {
			exprOut := $2[len($2) - 1].Outputs[0]
			switch $1 {
			case "*":
				exprOut.DereferenceLevels++
				exprOut.DereferenceOperations = append(exprOut.DereferenceOperations, DEREF_POINTER)
				if !exprOut.IsArrayFirst {
					exprOut.IsDereferenceFirst = true
				}
                
				exprOut.IsReference = false
			case "&":
				exprOut.IsReference = true
				exprOut.IsPointer = true
			}
			$$ = $2
                }
                ;

unary_operator:
                REF_OP
	|       MUL_OP
	|       ADD_OP
	|       SUB_OP
	|       NEG_OP
                ;

multiplicative_expression:
                unary_expression
	|       multiplicative_expression MUL_OP unary_expression
	|       multiplicative_expression '/' unary_expression
	|       multiplicative_expression '%' unary_expression
                ;

additive_expression:
                multiplicative_expression
	|       additive_expression ADD_OP multiplicative_expression
	|       additive_expression SUB_OP multiplicative_expression
                ;

shift_expression:
                additive_expression
	|       shift_expression LEFT_OP additive_expression
	|       shift_expression RIGHT_OP additive_expression
                ;

relational_expression:
                shift_expression
	|       relational_expression '<' shift_expression
	|       relational_expression '>' shift_expression
	|       relational_expression LE_OP shift_expression
	|       relational_expression GE_OP shift_expression
                ;

equality_expression:
                relational_expression
	|       equality_expression EQ_OP relational_expression
	|       equality_expression NE_OP relational_expression
                ;

and_expression: equality_expression
	|       and_expression REF_OP equality_expression
                ;

exclusive_or_expression:
                and_expression
	|       exclusive_or_expression '^' and_expression
                ;

inclusive_or_expression:
                exclusive_or_expression
	|       inclusive_or_expression '|' exclusive_or_expression
                ;

logical_and_expression:
                inclusive_or_expression
	|       logical_and_expression AND_OP inclusive_or_expression
                { $$ = nil }
                ;

logical_or_expression:
                logical_and_expression
	|       logical_or_expression OR_OP logical_and_expression
                ;

conditional_expression:
                logical_or_expression
	|       logical_or_expression '?' expression COLON conditional_expression
                ;

assignment_expression:
                conditional_expression
	|       unary_expression assignment_operator assignment_expression
                {
			if $3[0].IsStructLiteral{
				$$ = StructLiteralAssignment($1, $3)
			} else {
				
				$$ = Assignment($1, $3)
			}
                }
                ;

assignment_operator:
                ASSIGN
	|       MUL_ASSIGN
	|       DIV_ASSIGN
	|       MOD_ASSIGN
	|       ADD_ASSIGN
	|       SUB_ASSIGN
	|       LEFT_ASSIGN
	|       RIGHT_ASSIGN
	|       AND_ASSIGN
	|       XOR_ASSIGN
	|       OR_ASSIGN
                ;

expression:     assignment_expression
	|       expression COMMA assignment_expression
                {
			$$ = append($1, $3...)
                }
                ;

constant_expression:
                conditional_expression
                ;




declaration:
                VAR declarator declaration_specifiers SEMICOLON
                {
			// this will tell the runtime that it's just a declaration
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				expr := MakeExpression(nil)
				expr.Package = pkg

				$3.Name = $2.Name
				$3.Package = pkg
				expr.AddOutput($3)

				$$ = []*CXExpression{expr}
			} else {
				panic(err)
			}
                }
        |       VAR declarator declaration_specifiers ASSIGN initializer SEMICOLON
                {
			if pkg, err := prgrm.GetCurrentPackage(); err == nil {
				if $5[len($5) - 1].Operator == nil {
					// then it's a literal, e.g. var foo i32 = 10;
					expr := MakeExpression(Natives[OP_IDENTITY])
					expr.Package = pkg
					
					$3.Name = $2.Name
					$3.Package = pkg
					
					expr.AddOutput($3)
					expr.AddInput($5[len($5) - 1].Outputs[0])
					
					$$ = []*CXExpression{expr}
				} else {
					// then it's an expression (it has an operator)
					$3.Name = $2.Name
					$3.Package = pkg
					
					expr := $5[len($5) - 1]
					expr.AddOutput($3)
					
					// exprs := $5
					// exprs = append(exprs, expr)
					
					$$ = $5
				}
			} else {
				panic(err)
			}
                }
                ;

/* init_declarator: */
/*                 declarator '=' initializer */
/*                 { */
/*                     $$ = nil */
/*                 } */
/*         |       declarator */
/*                 { */
/*                     $$ = nil */
/*                 } */
/*                 ; */


/* init_declarator_list: */
/*                 init_declarator */
/*                 { */
/*                     $$ = nil */
/*                 } */
/* 	|       init_declarator_list COMMA init_declarator */
/*                 { */
/*                     $$ = nil */
/*                 } */
/*                 ; */

/* init_declarator: */
/*                 declarator '=' initializer */
/*                 { */
/*                     $$ = nil */
/*                 } */
/*         |       declarator */
/*                 { */
/*                     $$ = nil */
/*                 } */
/*                 ; */






initializer:
        /*         LBRACE initializer_list RBRACE */
	/* |       LBRACE   initializer_list COMMA RBRACE */
	/* |        */assignment_expression
                ;

initializer_list:
                designation initializer
                {
                    $$ = nil
                }
	|       initializer
                {
                    $$ = nil
                }
	|       initializer_list COMMA designation initializer
                {
                    $$ = nil
                }
	|       initializer_list COMMA initializer
                {
			$$ = nil
                }
                ;

designation:    designator_list ASSIGN
                {
			$$ = nil
                }
                ;

designator_list:
                designator
                {
			$$ = nil
                }
	|       designator_list designator
                {
			$$ = nil
                }
                ;

designator:
                LBRACK constant_expression RBRACK
                {
			$$ = nil
                }
	|       PERIOD IDENTIFIER
                {
                    $$ = nil
                }
                ;






// statements
statement:      /* labeled_statement */
	/* |        */compound_statement
	|       expression_statement
	|       selection_statement
	|       iteration_statement
	/* |       jump_statement */
                ;

labeled_statement:
                IDENTIFIER COLON statement
                { $$ = nil }
	|       CASE constant_expression COLON statement
                { $$ = nil }
	|       DEFAULT COLON statement
                { $$ = nil }
                ;

compound_statement:
                LBRACE RBRACE SEMICOLON
                { $$ = nil }
	|       LBRACE block_item_list RBRACE SEMICOLON
                {
                    $$ = $2
                }
                ;

block_item_list:
                block_item
	|       block_item_list block_item
                {
			$$ = append($1, $2...)
                }
                ;

block_item:     declaration
        |       statement
                ;

expression_statement:
                SEMICOLON
                { $$ = nil }
	|       expression SEMICOLON
                {
			if $1[len($1) - 1].Operator == nil {
				$$ = nil
			} else {
				$$ = $1
			}
                }
                ;

selection_statement:
                IF expression LBRACE block_item_list RBRACE elseif_list else_statement SEMICOLON
                {
			var lastElse []*CXExpression = $7
			for c := len($6) - 1; c >= 0; c-- {
				if lastElse != nil {
					lastElse = SelectionExpressions($6[c].Condition, $6[c].Then, lastElse)
				} else {
					lastElse = SelectionExpressions($6[c].Condition, $6[c].Then, nil)
				}
			}

			$$ = SelectionExpressions($2, $4, lastElse)
                }
        |       IF expression LBRACE block_item_list RBRACE else_statement SEMICOLON
                {
			$$ = SelectionExpressions($2, $4, $6)
                }
        |       IF expression LBRACE block_item_list RBRACE elseif_list SEMICOLON
                {
			var lastElse []*CXExpression
			for c := len($6) - 1; c >= 0; c-- {
				if lastElse != nil {
					lastElse = SelectionExpressions($6[c].Condition, $6[c].Then, lastElse)
				} else {
					lastElse = SelectionExpressions($6[c].Condition, $6[c].Then, nil)
				}
			}

			$$ = SelectionExpressions($2, $4, lastElse)
                }
        |       IF expression compound_statement
                {
			$$ = SelectionExpressions($2, $3, nil)
                }
	|       SWITCH LPAREN expression RPAREN statement
                { $$ = nil }
                ;

elseif:         ELSE IF expression LBRACE block_item_list RBRACE
                {
			$$ = selectStatement{
				Condition: $3,
				Then: $5,
			}
                }
                ;

elseif_list:    elseif
                {
			$$ = []selectStatement{$1}
                }
        |       elseif_list elseif
                {
			$$ = append($1, $2)
                }
        ;

else_statement:
                ELSE LBRACE block_item_list RBRACE
                {
			$$ = $3
                }
        ;



iteration_statement:
                FOR expression compound_statement
                {
			$$ = IterationExpressions(nil, $2, nil, $3)
                }
        |       FOR expression_statement expression_statement compound_statement
                {			
			$$ = IterationExpressions($2, $3, nil, $4)
                }
        |       FOR expression_statement expression_statement expression compound_statement
                {
			$$ = IterationExpressions($2, $3, $4, $5)
                }
                ;

jump_statement: GOTO IDENTIFIER SEMICOLON
                { $$ = nil }
	|       CONTINUE SEMICOLON
                { $$ = nil }
	|       BREAK SEMICOLON
                { $$ = nil }
	|       RETURN SEMICOLON
                { $$ = nil }
	|       RETURN expression SEMICOLON
                { $$ = nil }
                ;

%%
