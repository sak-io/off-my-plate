/// Accessibility identifiers of the List tab. The UI tests (`App/OffMyPlateUITests`) repeat
/// these strings; per-item ones end with the shopping item's raw id.
extension AccessibilityID {
    static let shoppingList = "shopping.list"
    static let shoppingLoading = "shopping.loading"
    static let shoppingError = "shopping.error"
    static let shoppingErrorRetry = "shopping.error.retry"
    static let shoppingNoPlan = "shopping.noPlan"
    static let shoppingGoToPlan = "shopping.goToPlan"
    static let shoppingNothing = "shopping.nothing"
    static let shoppingPending = "shopping.pending"
    static let shoppingRange = "shopping.range"
    static let shoppingAddField = "shopping.add"
    static let shoppingShare = "shopping.share"
    static let shoppingMenu = "shopping.menu"
    static let shoppingMenuBought = "shopping.menu.bought"
    static let shoppingMenuClear = "shopping.menu.clear"
    static let shoppingBought = "shopping.bought"
    static let shoppingBoughtConfirm = "shopping.bought.confirm"
    static let shoppingCheckSection = "shopping.section.checkYouHave"
    static func shoppingSection(_ aisle: String) -> String { "shopping.section.\(aisle)" }
    static func shoppingItem(_ id: String) -> String { "shopping.item.\(id)" }
    static func shoppingHaveIt(_ id: String) -> String { "shopping.haveIt.\(id)" }
    static func shoppingNeedIt(_ id: String) -> String { "shopping.needIt.\(id)" }
}
