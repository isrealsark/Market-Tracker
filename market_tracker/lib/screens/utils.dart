String money(double value) {
  // Format with 2 decimal places and add currency symbol
  return "₵${value.toStringAsFixed(2)}";
}
