// The browser module is a WASI reactor: JavaScript calls the exports in Exports.swift after `_initialize`.
// This file exists only because SwiftPM builds this product as an executable; in reactor mode `main`
// is never called.
