enum ApprovalBridge {
    func approveTapped() {
        let confirmation = UserConfirmation()
        service.approve(confirmation: confirmation)
    }
}
