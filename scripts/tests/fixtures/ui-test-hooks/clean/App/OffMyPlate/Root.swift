// -OMPUITestSeed is only mentioned in this comment.
func make() {
    #if DEBUG
    let a = "-OMPUITestSeed"
    #if os(iOS)
    let b = "-OMPUITestInbox"
    #else
    let c = "-OMPUITestSpeech"
    #endif
    #endif
}
