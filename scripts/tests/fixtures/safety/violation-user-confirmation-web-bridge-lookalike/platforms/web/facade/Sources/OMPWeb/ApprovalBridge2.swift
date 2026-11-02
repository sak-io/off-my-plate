enum ApprovalBridge2 {
    func approve() {
        let confirmation = UserConfirmation()
        service.approve(confirmation: confirmation)
    }
}
