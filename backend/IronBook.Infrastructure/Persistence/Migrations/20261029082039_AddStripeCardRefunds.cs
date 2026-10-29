using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace IronBook.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddStripeCardRefunds : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "StripeRefundId",
                table: "Payments",
                type: "nvarchar(255)",
                maxLength: 255,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Payments_StripeRefundId",
                table: "Payments",
                column: "StripeRefundId",
                unique: true,
                filter: "[StripeRefundId] IS NOT NULL");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Payments_StripeRefund",
                table: "Payments",
                sql: "([StripeRefundId] IS NULL OR ([PaymentMethod] = 'Card' AND [StripePaymentIntentId] IS NOT NULL)) AND ([PaymentStatus] NOT IN ('RefundPending', 'Refunded') OR [StripeRefundId] IS NOT NULL)");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Payments_StripeRefundId",
                table: "Payments");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Payments_StripeRefund",
                table: "Payments");

            migrationBuilder.DropColumn(
                name: "StripeRefundId",
                table: "Payments");
        }
    }
}
