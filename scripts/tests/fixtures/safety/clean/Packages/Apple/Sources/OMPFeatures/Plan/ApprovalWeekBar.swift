struct ApprovalWeekBar {
    func approveTapped() {
        let confirmation = UserConfirmation()
        model.approve(confirmation: confirmation)
    }
}
