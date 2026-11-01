struct ApprovalSheet {
    func approveTapped() {
        let confirmation = UserConfirmation()
        model.approve(confirmation: confirmation)
    }
}
