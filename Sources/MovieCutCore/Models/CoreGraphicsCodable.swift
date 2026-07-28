import Foundation

// CGPoint and CGSize are NOT given a local `@retroactive Codable` /
// `@retroactive Equatable` conformance here.
//
// Earlier this file declared one, producing a duplicate-conformance warning
// ("conformance of 'CGPoint' to protocol 'Decodable' was already stated in
// the protocol's module 'CoreGraphics'", x6). On this toolchain CoreGraphics'
// native conformance wins and serializes the array form `[x, y]` / `[width,
// height]`; the local keyed form `{"x":..}` was therefore dead code on both
// encode and decode. The winner of such a conflict is not language-guaranteed,
// which is why the conformances were removed: relying on CoreGraphics' native
// Codable (array form) removes the ambiguity entirely.
//
// The on-disk array form is pinned by `Tests/Fixtures/cg_codable_parity.moviecut`,
// which exercises every Codable CG field (mask position/size/brushPoints, clip
// transform position/offset/scale/anchorPoint, text position/shadowOffset,
// timeline canvasSize). That fixture must keep loading losslessly across any
// future change touching CG persistence.
//
// If a model ever needs a *different* on-disk shape for a point or size, give
// that field an explicit wrapper type (see the historical A-option in the
// reliability repair work order) rather than re-introducing a retroactive
// conformance here.
