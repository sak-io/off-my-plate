struct ApprovalShortcut {
    func tapped() {
        model.approve(confirmation: UserConfirmation())
    }
}
