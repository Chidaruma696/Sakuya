module ReviewsHelper
  # Where the reviewed operation links to.
  def link_of_review(review)
    r = review.reviewable
    case r
    when Movement then kardex_inventory_path(product_id: r.product_id, branch_id: r.branch_id)
    when Withdrawal then till_shift_path
    when SaleLine then till_ticket_path(r.sale)
    when Sale then till_ticket_path(r)
    when Receipt then receipt_path(r)
    when Product then kardex_inventory_path(product_id: r.id, branch_id: review.branch_id)
    when Supplier then invoices_path(supplier_id: r.id)
    else reviews_path
    end
  end
end
