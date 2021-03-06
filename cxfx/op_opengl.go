// +build cxfx

package cxfx

import (
	"bufio"
	"fmt"
	. "github.com/SkycoinProject/cx/cx"
	"image"
	"image/draw"
	"image/gif"
	_ "image/jpeg"
	_ "image/png"
	"runtime"
)

var gifs map[string]*gif.GIF = make(map[string]*gif.GIF, 0)

func uploadTexture(file string, target uint32) {

	imgFile, err := CXOpenFile(file)
	if err != nil {
		panic(fmt.Sprintf("texture %q not found on disk: %v\n", file, err))
	}

	img, _, err := image.Decode(imgFile)
	if err != nil {
		panic(err)
	}

	rgba := image.NewRGBA(img.Bounds())
	if rgba.Stride != rgba.Rect.Size().X*4 {
		panic("unsupported stride")
	}

	draw.Draw(rgba, rgba.Bounds(), img, image.Point{0, 0}, draw.Src)

	cxglTexImage2D(
		target,
		0,
		cxglRGBA,
		int32(rgba.Rect.Size().X),
		int32(rgba.Rect.Size().Y),
		0,
		cxglRGBA,
		cxglUNSIGNED_BYTE,
		rgba.Pix)
}

// gogl
func opGlNewTexture(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	var texture uint32
	cxglEnable(cxglTEXTURE_2D)
	cxglGenTextures(1, &texture)
	cxglBindTexture(cxglTEXTURE_2D, texture)
	cxglTexParameteri(cxglTEXTURE_2D, cxglTEXTURE_MIN_FILTER, cxglNEAREST)
	cxglTexParameteri(cxglTEXTURE_2D, cxglTEXTURE_MAG_FILTER, cxglNEAREST)
	cxglTexParameteri(cxglTEXTURE_2D, cxglTEXTURE_WRAP_S, cxglCLAMP_TO_EDGE)
	cxglTexParameteri(cxglTEXTURE_2D, cxglTEXTURE_WRAP_T, cxglCLAMP_TO_EDGE)

	uploadTexture(ReadStr(fp, expr.Inputs[0]), cxglTEXTURE_2D)

	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), int32(texture))
}

func opGlNewTextureCube(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	var texture uint32
	cxglEnable(cxglTEXTURE_CUBE_MAP)
	cxglGenTextures(1, &texture)
	cxglBindTexture(cxglTEXTURE_CUBE_MAP, texture)
	cxglTexParameteri(cxglTEXTURE_CUBE_MAP, cxglTEXTURE_MIN_FILTER, cxglNEAREST)
	cxglTexParameteri(cxglTEXTURE_CUBE_MAP, cxglTEXTURE_MAG_FILTER, cxglNEAREST)
	cxglTexParameteri(cxglTEXTURE_CUBE_MAP, cxglTEXTURE_WRAP_S, cxglCLAMP_TO_EDGE)
	cxglTexParameteri(cxglTEXTURE_CUBE_MAP, cxglTEXTURE_WRAP_T, cxglCLAMP_TO_EDGE)
	cxglTexParameteri(cxglTEXTURE_CUBE_MAP, cxglTEXTURE_WRAP_R, cxglCLAMP_TO_EDGE)

	var faces []string = []string{"posx", "negx", "posy", "negy", "posz", "negz"}
	var pattern string = ReadStr(fp, expr.Inputs[0])
	var extension string = ReadStr(fp, expr.Inputs[1])
	for i := 0; i < 6; i++ {
		uploadTexture(fmt.Sprintf("%s%s%s", pattern, faces[i], extension), uint32(cxglTEXTURE_CUBE_MAP_POSITIVE_X+i))
	}
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), int32(texture))
}

func opGlUploadImageToTexture(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	uploadTexture(ReadStr(fp, expr.Inputs[0]), uint32(ReadI32(fp, expr.Inputs[1])))
}

func opGlNewGIF(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	path := ReadStr(fp, expr.Inputs[0])

	file, err := CXOpenFile(path)
	defer file.Close()
	if err != nil {
		panic(fmt.Sprintf("file not found %q, %v", path, err))
	}

	reader := bufio.NewReader(file)
	gif, err := gif.DecodeAll(reader)
	if err != nil {
		panic(fmt.Sprintf("failed to decode file %q, %v", path, err))
	}

	gifs[path] = gif

	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), int32(len(gif.Image)))
	WriteI32(GetFinalOffset(fp, expr.Outputs[1]), int32(gif.LoopCount))
	WriteI32(GetFinalOffset(fp, expr.Outputs[2]), int32(gif.Config.Width))
	WriteI32(GetFinalOffset(fp, expr.Outputs[3]), int32(gif.Config.Height))
}

func opGlFreeGIF(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	gifs[ReadStr(fp, expr.Inputs[0])] = nil
}

func opGlGIFFrameToTexture(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	path := ReadStr(fp, expr.Inputs[0])
	frame := ReadI32(fp, expr.Inputs[1])
	texture := ReadI32(fp, expr.Inputs[2])

	gif := gifs[path]
	img := gif.Image[frame]
	delay := int32(gif.Delay[frame])
	disposal := int32(gif.Disposal[frame])

	rgba := image.NewRGBA(img.Bounds())
	draw.Draw(rgba, rgba.Bounds(), img, image.Point{0, 0}, draw.Src)

	cxglBindTexture(cxglTEXTURE_2D, uint32(texture))
	cxglTexImage2D(
		cxglTEXTURE_2D,
		0,
		cxglRGBA,
		int32(rgba.Rect.Size().X),
		int32(rgba.Rect.Size().Y),
		0,
		cxglRGBA,
		cxglUNSIGNED_BYTE,
		rgba.Pix)

	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), delay)
	WriteI32(GetFinalOffset(fp, expr.Outputs[1]), disposal)
}

func opGlAppend(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	outputSlicePointer := GetFinalOffset(fp, expr.Outputs[0])
	outputSliceOffset := GetPointerOffset(int32(outputSlicePointer))

	inputSliceOffset := GetSliceOffset(fp, expr.Inputs[0])
	var inputSliceLen int32
	if inputSliceOffset != 0 {
		inputSliceLen = GetSliceLen(inputSliceOffset)
	}

	inp1 := expr.Inputs[1]
	obj := ReadMemory(GetFinalOffset(fp, inp1), inp1)

	objLen := int32(len(obj))
	outputSliceOffset = int32(SliceResizeEx(outputSliceOffset, inputSliceLen+objLen, 1))
	SliceCopyEx(outputSliceOffset, inputSliceOffset, inputSliceLen+objLen, 1)
	SliceAppendWriteByte(outputSliceOffset, obj, inputSliceLen)
	WriteI32(outputSlicePointer, outputSliceOffset)
}

// gl_1_0
func opGlCullFace(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglCullFace(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlFrontFace(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglFrontFace(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlHint(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglHint(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])))
}

func opGlScissor(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglScissor(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadI32(fp, expr.Inputs[2]),
		ReadI32(fp, expr.Inputs[3]))
}

func opGlTexParameteri(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglTexParameteri(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])),
		ReadI32(fp, expr.Inputs[2]))
}

func opGlTexImage2D(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglTexImage2D(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]),
		ReadI32(fp, expr.Inputs[2]),
		ReadI32(fp, expr.Inputs[3]),
		ReadI32(fp, expr.Inputs[4]),
		ReadI32(fp, expr.Inputs[5]),
		uint32(ReadI32(fp, expr.Inputs[6])),
		uint32(ReadI32(fp, expr.Inputs[7])),
		ReadData(fp, expr.Inputs[8], -1))
}

func opGlClear(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglClear(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlClearColor(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglClearColor(
		ReadF32(fp, expr.Inputs[0]),
		ReadF32(fp, expr.Inputs[1]),
		ReadF32(fp, expr.Inputs[2]),
		ReadF32(fp, expr.Inputs[3]))
}

func opGlClearStencil(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglClearStencil(ReadI32(fp, expr.Inputs[0]))
}

func opGlClearDepth(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglClearDepth(ReadF64(fp, expr.Inputs[0]))
}

func opGlStencilMask(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglStencilMask(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlColorMask(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglColorMask(
		ReadBool(fp, expr.Inputs[0]),
		ReadBool(fp, expr.Inputs[1]),
		ReadBool(fp, expr.Inputs[2]),
		ReadBool(fp, expr.Inputs[3]))
}

func opGlDepthMask(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglDepthMask(ReadBool(fp, expr.Inputs[0]))
}

func opGlDisable(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()
	cxglDisable(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlEnable(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglEnable(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlBlendFunc(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglBlendFunc(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])))
}

func opGlStencilFunc(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglStencilFunc(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]),
		uint32(ReadI32(fp, expr.Inputs[2])))
}

func opGlStencilOp(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglStencilOp(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])),
		uint32(ReadI32(fp, expr.Inputs[2])))
}

func opGlDepthFunc(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglDepthFunc(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlGetError(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), int32(cxglGetError()))
}

func opGlGetTexLevelParameteriv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	var outValue int32 = 0
	cxglGetTexLevelParameteriv(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]),
		uint32(ReadI32(fp, expr.Inputs[2])),
		&outValue)
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), outValue)
}

func opGlDepthRange(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglDepthRange(
		ReadF64(fp, expr.Inputs[0]),
		ReadF64(fp, expr.Inputs[1]))
}

func opGlViewport(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglViewport(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadI32(fp, expr.Inputs[2]),
		ReadI32(fp, expr.Inputs[3]))
}

// gl_1_1
func opGlDrawArrays(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglDrawArrays(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]),
		ReadI32(fp, expr.Inputs[2]))
}

func opGlDrawElements(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglDrawElements(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]),
		uint32(ReadI32(fp, expr.Inputs[2])),
		ReadData(fp, expr.Inputs[3], -1))
}

func opGlBindTexture(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglBindTexture(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])))
}

func opGlDeleteTextures(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV1 := uint32(ReadI32(fp, expr.Inputs[1]))
	cxglDeleteTextures(ReadI32(fp, expr.Inputs[0]), &inpV1) // will panic if inp0 > 1
}

func opGlGenTextures(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV1 := uint32(ReadI32(fp, expr.Inputs[1]))
	cxglGenTextures(ReadI32(fp, expr.Inputs[0]), &inpV1) // will panic if inp0 > 1
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), int32(inpV1))
}

// gl_1_3
func opGlActiveTexture(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglActiveTexture(uint32(ReadI32(fp, expr.Inputs[0])))
}

// gl_1_4
func opGlBlendFuncSeparate(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglBlendFuncSeparate(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])),
		uint32(ReadI32(fp, expr.Inputs[2])),
		uint32(ReadI32(fp, expr.Inputs[3])))
}

// gl_1_5
func opGlBindBuffer(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglBindBuffer(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])))
}

func opGlDeleteBuffers(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV1 := uint32(ReadI32(fp, expr.Inputs[1]))
	cxglDeleteBuffers(
		ReadI32(fp, expr.Inputs[0]),
		&inpV1) // will panic if inp0 > 1
}

func opGlGenBuffers(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV1 := uint32(ReadI32(fp, expr.Inputs[1]))
	cxglGenBuffers(
		ReadI32(fp, expr.Inputs[0]),
		&inpV1) // will panic if inp0 > 1
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), int32(inpV1))
}

func opGlBufferData(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglBufferData(
		uint32(ReadI32(fp, expr.Inputs[0])),
		int(ReadI32(fp, expr.Inputs[1])),
		ReadData(fp, expr.Inputs[2], -1),
		uint32(ReadI32(fp, expr.Inputs[3])))
}

func opGlBufferSubData(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglBufferSubData(
		uint32(ReadI32(fp, expr.Inputs[0])),
		int(ReadI32(fp, expr.Inputs[1])),
		int(ReadI32(fp, expr.Inputs[2])),
		ReadData(fp, expr.Inputs[3], -1))
}

func opGlDrawBuffers(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglDrawBuffers(
		ReadI32(fp, expr.Inputs[0]),
		ReadData(fp, expr.Inputs[1], TYPE_UI32))
}

func opGlStencilOpSeparate(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglStencilOpSeparate(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])),
		uint32(ReadI32(fp, expr.Inputs[2])),
		uint32(ReadI32(fp, expr.Inputs[3])))
}

func opGlStencilFuncSeparate(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglStencilFuncSeparate(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])),
		ReadI32(fp, expr.Inputs[2]),
		uint32(ReadI32(fp, expr.Inputs[3])))
}

func opGlStencilMaskSeparate(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglStencilMaskSeparate(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])))
}

func opGlAttachShader(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglAttachShader(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])))
}

func opGlBindAttribLocation(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglBindAttribLocation(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])),
		ReadStr(fp, expr.Inputs[2]))
}

func opGlCompileShader(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	shader := uint32(ReadI32(fp, expr.Inputs[0]))
	cxglCompileShader(shader)
}

func opGlCreateProgram(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), int32(cxglCreateProgram()))
}

func opGlCreateShader(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	outV0 := int32(cxglCreateShader(uint32(ReadI32(fp, expr.Inputs[0]))))
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), outV0)
}

func opGlDeleteProgram(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglDeleteShader(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlDeleteShader(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglDeleteShader(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlDetachShader(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglDetachShader(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])))
}

func opGlEnableVertexAttribArray(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglEnableVertexAttribArray(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlGetAttribLocation(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	outV0 := cxglGetAttribLocation(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadStr(fp, expr.Inputs[1]))
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), outV0)
}

func opGlGetProgramiv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	outV0 := cxglGetProgramiv(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])))
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), outV0)
}

func opGlGetProgramInfoLog(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	outV0 := cxglGetProgramInfoLog(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]))
	WriteObject(GetFinalOffset(fp, expr.Outputs[0]), FromStr(outV0))
}

func opGlGetShaderiv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	outV0 := cxglGetShaderiv(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])))
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), outV0)
}

func opGlGetShaderInfoLog(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	outV0 := cxglGetShaderInfoLog(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]))
	WriteObject(GetFinalOffset(fp, expr.Outputs[0]), FromStr(outV0))
}

func opGlGetUniformLocation(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	outV0 := cxglGetUniformLocation(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadStr(fp, expr.Inputs[1]))
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), outV0)
}

func opGlLinkProgram(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	program := uint32(ReadI32(fp, expr.Inputs[0]))
	cxglLinkProgram(program)
}

func opGlShaderSource(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglShaderSource(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]),
		ReadStr(fp, expr.Inputs[2]))
}

func opGlUseProgram(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUseProgram(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlUniform1f(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform1f(
		ReadI32(fp, expr.Inputs[0]),
		ReadF32(fp, expr.Inputs[1]))
}

func opGlUniform2f(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform2f(
		ReadI32(fp, expr.Inputs[0]),
		ReadF32(fp, expr.Inputs[1]),
		ReadF32(fp, expr.Inputs[2]))
}

func opGlUniform3f(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform3f(
		ReadI32(fp, expr.Inputs[0]),
		ReadF32(fp, expr.Inputs[1]),
		ReadF32(fp, expr.Inputs[2]),
		ReadF32(fp, expr.Inputs[3]))
}

func opGlUniform4f(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform4f(
		ReadI32(fp, expr.Inputs[0]),
		ReadF32(fp, expr.Inputs[1]),
		ReadF32(fp, expr.Inputs[2]),
		ReadF32(fp, expr.Inputs[3]),
		ReadF32(fp, expr.Inputs[4]))
}

func opGlUniform1i(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform1i(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]))
}

func opGlUniform2i(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform2i(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadI32(fp, expr.Inputs[2]))
}

func opGlUniform3i(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform3i(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadI32(fp, expr.Inputs[2]),
		ReadI32(fp, expr.Inputs[3]))
}

func opGlUniform4i(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform4i(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadI32(fp, expr.Inputs[2]),
		ReadI32(fp, expr.Inputs[3]),
		ReadI32(fp, expr.Inputs[4]))
}

func opGlUniform1fv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform1fv(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadData(fp, expr.Inputs[2], TYPE_F32))
}

func opGlUniform2fv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform2fv(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadData(fp, expr.Inputs[2], TYPE_F32))
}

func opGlUniform3fv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform3fv(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadData(fp, expr.Inputs[2], TYPE_F32))
}

func opGlUniform4fv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform4fv(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadData(fp, expr.Inputs[2], TYPE_F32))
}

func opGlUniform1iv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform1iv(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadData(fp, expr.Inputs[2], TYPE_I32))
}

func opGlUniform2iv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform2iv(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadData(fp, expr.Inputs[2], TYPE_I32))
}

func opGlUniform3iv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform3iv(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadData(fp, expr.Inputs[2], TYPE_I32))
}

func opGlUniform4iv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform4iv(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadData(fp, expr.Inputs[2], TYPE_I32))
}

func opGlUniformMatrix2fv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniformMatrix2fv(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadBool(fp, expr.Inputs[2]),
		ReadData(fp, expr.Inputs[3], TYPE_F32))
}

func opGlUniformMatrix3fv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniformMatrix3fv(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadBool(fp, expr.Inputs[2]),
		ReadData(fp, expr.Inputs[3], TYPE_F32))
}

func opGlUniformMatrix4fv(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniformMatrix4fv(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadBool(fp, expr.Inputs[2]),
		ReadData(fp, expr.Inputs[3], TYPE_F32))
}

func opGlUniformV4F(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniform4fv(
		ReadI32(fp, expr.Inputs[0]),
		1,
		ReadData(fp, expr.Inputs[1], -1))
}

func opGlUniformM44F(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniformMatrix4fv(
		ReadI32(fp, expr.Inputs[0]),
		1,
		ReadBool(fp, expr.Inputs[1]),
		ReadData(fp, expr.Inputs[2], -1))
}

func opGlUniformM44FV(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglUniformMatrix4fv(
		ReadI32(fp, expr.Inputs[0]),
		ReadI32(fp, expr.Inputs[1]),
		ReadBool(fp, expr.Inputs[2]),
		ReadData(fp, expr.Inputs[3], -1))
}

func opGlVertexAttribPointer(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglVertexAttribPointer(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]),
		uint32(ReadI32(fp, expr.Inputs[2])),
		ReadBool(fp, expr.Inputs[3]),
		ReadI32(fp, expr.Inputs[4]), 0)
}

func opGlVertexAttribPointerI32(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglVertexAttribPointer(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]),
		uint32(ReadI32(fp, expr.Inputs[2])),
		ReadBool(fp, expr.Inputs[3]),
		ReadI32(fp, expr.Inputs[4]),
		ReadI32(fp, expr.Inputs[5]))
}

func opGlClearBufferI(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	color := []int32{
		ReadI32(fp, expr.Inputs[2]),
		ReadI32(fp, expr.Inputs[3]),
		ReadI32(fp, expr.Inputs[4]),
		ReadI32(fp, expr.Inputs[5])}

	cxglClearBufferiv(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]),
		color)
}

func opGlClearBufferUI(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	color := []uint32{
		ReadUI32(fp, expr.Inputs[2]),
		ReadUI32(fp, expr.Inputs[3]),
		ReadUI32(fp, expr.Inputs[4]),
		ReadUI32(fp, expr.Inputs[5])}

	cxglClearBufferuiv(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]),
		color)
}

func opGlClearBufferF(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	color := []float32{
		ReadF32(fp, expr.Inputs[2]),
		ReadF32(fp, expr.Inputs[3]),
		ReadF32(fp, expr.Inputs[4]),
		ReadF32(fp, expr.Inputs[5])}

	cxglClearBufferfv(
		uint32(ReadI32(fp, expr.Inputs[0])),
		ReadI32(fp, expr.Inputs[1]),
		color)
}

func opGlBindRenderbuffer(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglBindRenderbuffer(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])))
}

func opGlDeleteRenderbuffers(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV1 := uint32(ReadI32(fp, expr.Inputs[1]))
	cxglDeleteRenderbuffers(ReadI32(fp, expr.Inputs[0]), &inpV1) // will panic if inp0 > 1
}

func opGlGenRenderbuffers(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV1 := uint32(ReadI32(fp, expr.Inputs[1]))
	cxglGenRenderbuffers(ReadI32(fp, expr.Inputs[0]), &inpV1) // will panic if inp0 > 1
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), int32(inpV1))
}

func opGlRenderbufferStorage(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglRenderbufferStorage(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])),
		ReadI32(fp, expr.Inputs[2]),
		ReadI32(fp, expr.Inputs[3]))
}

func opGlBindFramebuffer(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglBindFramebuffer(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])))
}

func opGlDeleteFramebuffers(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV1 := uint32(ReadI32(fp, expr.Inputs[1]))
	cxglDeleteFramebuffers(ReadI32(fp, expr.Inputs[0]), &inpV1) // will panic if inp0 > 1
}

func opGlGenFramebuffers(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV1 := uint32(ReadI32(fp, expr.Inputs[1]))
	cxglGenFramebuffers(ReadI32(fp, expr.Inputs[0]), &inpV1) // will panic if inp0 > 1
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), int32(inpV1))
}

func opGlCheckFramebufferStatus(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	outV0 := int32(cxglCheckFramebufferStatus(uint32(ReadI32(fp, expr.Inputs[0]))))
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), outV0)
}

func opGlFramebufferTexture2D(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglFramebufferTexture2D(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])),
		uint32(ReadI32(fp, expr.Inputs[2])),
		uint32(ReadI32(fp, expr.Inputs[3])),
		ReadI32(fp, expr.Inputs[4]))
}

func opGlFramebufferRenderbuffer(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglFramebufferRenderbuffer(
		uint32(ReadI32(fp, expr.Inputs[0])),
		uint32(ReadI32(fp, expr.Inputs[1])),
		uint32(ReadI32(fp, expr.Inputs[2])),
		uint32(ReadI32(fp, expr.Inputs[3])))
}

func opGlGenerateMipmap(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglGenerateMipmap(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlBindVertexArray(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV0 := uint32(ReadI32(fp, expr.Inputs[0]))
	if runtime.GOOS == "darwin" {
		cxglBindVertexArrayAPPLE(inpV0)
	} else {
		cxglBindVertexArray(inpV0)
	}
}

func opGlBindVertexArrayCore(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	cxglBindVertexArray(uint32(ReadI32(fp, expr.Inputs[0])))
}

func opGlDeleteVertexArrays(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV0 := ReadI32(fp, expr.Inputs[0])
	inpV1 := uint32(ReadI32(fp, expr.Inputs[1]))
	if runtime.GOOS == "darwin" {
		cxglDeleteVertexArraysAPPLE(inpV0, &inpV1) // will panic if inp0 > 1
	} else {
		cxglDeleteVertexArrays(inpV0, &inpV1) // will panic if inp0 > 1
	}
}

func opGlDeleteVertexArraysCore(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV1 := uint32(ReadI32(fp, expr.Inputs[1]))
	cxglDeleteVertexArrays(ReadI32(fp, expr.Inputs[0]), &inpV1) // will panic if inp0 > 1
}

func opGlGenVertexArrays(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV0 := ReadI32(fp, expr.Inputs[0])
	inpV1 := uint32(ReadI32(fp, expr.Inputs[1]))
	if runtime.GOOS == "darwin" {
		cxglGenVertexArraysAPPLE(inpV0, &inpV1) // will panic if inp0 > 1
	} else {
		cxglGenVertexArrays(inpV0, &inpV1) // will panic if inp0 > 1
	}
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), int32(inpV1))
}

func opGlGenVertexArraysCore(prgrm *CXProgram) {
	expr := prgrm.GetExpr()
	fp := prgrm.GetFramePointer()

	inpV1 := uint32(ReadI32(fp, expr.Inputs[1]))
	cxglGenVertexArrays(ReadI32(fp, expr.Inputs[0]), &inpV1) // will panic if inp0 > 1
	WriteI32(GetFinalOffset(fp, expr.Outputs[0]), int32(inpV1))
}
