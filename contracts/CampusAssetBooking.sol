// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CampusAssetBooking
 * @notice Decentralized campus resource booking with access control,
 *         conflict detection, and tiered refund policy.
 * @dev Deploy on Ganache (chainId 1337). Admin is msg.sender at deployment.
 */
contract CampusAssetBooking {

    // ─────────────────────────────────────────────────────────────────────────
    // DATA STRUCTURES
    // ─────────────────────────────────────────────────────────────────────────

    struct Asset {
        uint256 id;
        string  name;
        string  description;
        string  category;        // e.g. "Lab", "Hall", "Equipment", "Court"
        uint256 hourlyFeeWei;    // price per hour in wei
        bool    active;
        address registeredBy;
        uint256 createdAt;
    }

    enum BookingStatus { Active, CancelledByAdmin, CancelledByUser }

    struct Booking {
        uint256 id;
        uint256 assetId;
        address bookedBy;
        uint256 startTime;       // unix timestamp
        uint256 endTime;         // unix timestamp
        uint256 amountPaid;      // wei paid
        BookingStatus status;
        uint256 createdAt;
        uint256 cancelledAt;
        uint256 refundAmount;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────────────────────────────────────

    address public admin;

    uint256 private _nextAssetId   = 1;
    uint256 private _nextBookingId = 1;

    // assetId → Asset
    mapping(uint256 => Asset) public assets;
    uint256[] public assetIds;

    // bookingId → Booking
    mapping(uint256 => Booking) public bookings;
    uint256[] public bookingIds;

    // Registered user wallets
    mapping(address => bool) public registeredUsers;
    address[] public registeredUserList;

    // assetId → list of active booking ids (for conflict check)
    mapping(uint256 => uint256[]) private _assetBookings;

    // user → booking ids
    mapping(address => uint256[]) private _userBookings;

    // ─────────────────────────────────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────────────────────────────────

    event UserRegistered(address indexed user, uint256 timestamp);
    event UserRemoved(address indexed user, uint256 timestamp);
    event AssetRegistered(uint256 indexed assetId, string name, uint256 hourlyFeeWei);
    event AssetUpdated(uint256 indexed assetId, string name, uint256 hourlyFeeWei);
    event AssetDeactivated(uint256 indexed assetId);
    event BookingCreated(
        uint256 indexed bookingId,
        uint256 indexed assetId,
        address indexed bookedBy,
        uint256 startTime,
        uint256 endTime,
        uint256 amountPaid
    );
    event BookingCancelledByAdmin(uint256 indexed bookingId, uint256 refund);
    event BookingCancelledByUser(uint256 indexed bookingId, uint256 refund);

    // ─────────────────────────────────────────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyAdmin() {
        require(msg.sender == admin, "CampusBooking: caller is not admin");
        _;
    }

    modifier onlyRegistered() {
        require(registeredUsers[msg.sender], "CampusBooking: wallet not registered");
        _;
    }

    modifier assetExists(uint256 assetId) {
        require(assets[assetId].active, "CampusBooking: asset not found or inactive");
        _;
    }

    modifier bookingExists(uint256 bookingId) {
        require(bookingId > 0 && bookingId < _nextBookingId, "CampusBooking: booking not found");
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────────────────────────────────

    constructor() {
        admin = msg.sender;
        // Admin is auto-registered so they can also make bookings if needed
        registeredUsers[msg.sender] = true;
        registeredUserList.push(msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ADMIN: USER MANAGEMENT
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Register a wallet so it can book assets.
     */
    function registerUser(address user) external onlyAdmin {
        require(user != address(0), "CampusBooking: zero address");
        require(!registeredUsers[user], "CampusBooking: already registered");
        registeredUsers[user] = true;
        registeredUserList.push(user);
        emit UserRegistered(user, block.timestamp);
    }

    /**
     * @notice Batch-register multiple wallets.
     */
    function registerUsers(address[] calldata users) external onlyAdmin {
        for (uint256 i = 0; i < users.length; i++) {
            if (!registeredUsers[users[i]] && users[i] != address(0)) {
                registeredUsers[users[i]] = true;
                registeredUserList.push(users[i]);
                emit UserRegistered(users[i], block.timestamp);
            }
        }
    }

    /**
     * @notice Revoke a wallet's booking privileges.
     */
    function removeUser(address user) external onlyAdmin {
        require(registeredUsers[user], "CampusBooking: not registered");
        require(user != admin, "CampusBooking: cannot remove admin");
        registeredUsers[user] = false;
        emit UserRemoved(user, block.timestamp);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ADMIN: ASSET MANAGEMENT
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Register a new bookable asset.
     * @param name         Human-readable name (e.g. "Seminar Hall A")
     * @param description  Details about the asset
     * @param category     Category tag
     * @param hourlyFeeWei Fee per hour in wei
     */
    function registerAsset(
        string calldata name,
        string calldata description,
        string calldata category,
        uint256 hourlyFeeWei
    ) external onlyAdmin returns (uint256 assetId) {
        require(bytes(name).length > 0, "CampusBooking: name required");
        require(hourlyFeeWei > 0,       "CampusBooking: fee must be > 0");

        assetId = _nextAssetId++;
        assets[assetId] = Asset({
            id:            assetId,
            name:          name,
            description:   description,
            category:      category,
            hourlyFeeWei:  hourlyFeeWei,
            active:        true,
            registeredBy:  msg.sender,
            createdAt:     block.timestamp
        });
        assetIds.push(assetId);
        emit AssetRegistered(assetId, name, hourlyFeeWei);
    }

    /**
     * @notice Update asset metadata and/or fee (does not affect existing bookings).
     */
    function updateAsset(
        uint256 assetId,
        string calldata name,
        string calldata description,
        string calldata category,
        uint256 hourlyFeeWei
    ) external onlyAdmin assetExists(assetId) {
        Asset storage a = assets[assetId];
        a.name         = name;
        a.description  = description;
        a.category     = category;
        a.hourlyFeeWei = hourlyFeeWei;
        emit AssetUpdated(assetId, name, hourlyFeeWei);
    }

    /**
     * @notice Deactivate an asset (soft-delete, history preserved).
     */
    function deactivateAsset(uint256 assetId) external onlyAdmin assetExists(assetId) {
        assets[assetId].active = false;
        emit AssetDeactivated(assetId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // BOOKING
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Book an asset for a time slot.
     * @param assetId   Target asset
     * @param startTime Unix timestamp for slot start
     * @param endTime   Unix timestamp for slot end (must be after startTime)
     *
     * msg.value must equal (endTime - startTime) / 3600 * hourlyFeeWei
     * (integer hours only, minimum 1 hour).
     *
     * Reverts on overlap with any existing active booking.
     * Excess ETH is NOT accepted — must send exact amount.
     */
    function bookAsset(
        uint256 assetId,
        uint256 startTime,
        uint256 endTime
    ) external payable onlyRegistered assetExists(assetId) returns (uint256 bookingId) {

        // ── Validate times ──────────────────────────────────────────────────
        require(startTime >= block.timestamp, "CampusBooking: start time in the past");
        require(endTime > startTime,          "CampusBooking: end must be after start");
        uint256 durationSecs = endTime - startTime;
        require(durationSecs >= 3600,         "CampusBooking: minimum 1 hour");
        require(durationSecs % 3600 == 0,     "CampusBooking: duration must be whole hours");

        // ── Validate payment ────────────────────────────────────────────────
        uint256 hours_  = durationSecs / 3600;
        uint256 required = hours_ * assets[assetId].hourlyFeeWei;
        require(msg.value == required, "CampusBooking: incorrect ETH amount");

        // ── Conflict detection ──────────────────────────────────────────────
        _rejectIfConflict(assetId, startTime, endTime);

        // ── Record booking ──────────────────────────────────────────────────
        bookingId = _nextBookingId++;
        bookings[bookingId] = Booking({
            id:           bookingId,
            assetId:      assetId,
            bookedBy:     msg.sender,
            startTime:    startTime,
            endTime:      endTime,
            amountPaid:   msg.value,
            status:       BookingStatus.Active,
            createdAt:    block.timestamp,
            cancelledAt:  0,
            refundAmount: 0
        });
        bookingIds.push(bookingId);
        _assetBookings[assetId].push(bookingId);
        _userBookings[msg.sender].push(bookingId);

        emit BookingCreated(bookingId, assetId, msg.sender, startTime, endTime, msg.value);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CANCELLATION
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Admin cancels any booking → 100% refund.
     */
    function adminCancelBooking(uint256 bookingId)
        external
        onlyAdmin
        bookingExists(bookingId)
    {
        Booking storage b = bookings[bookingId];
        require(b.status == BookingStatus.Active, "CampusBooking: booking not active");

        uint256 refund = b.amountPaid;
        b.status       = BookingStatus.CancelledByAdmin;
        b.cancelledAt  = block.timestamp;
        b.refundAmount = refund;

        _sendRefund(b.bookedBy, refund);
        emit BookingCancelledByAdmin(bookingId, refund);
    }

    /**
     * @notice User cancels their own booking.
     *  - > 24 hours before start → 100% refund
     *  - ≤ 24 hours before start → 50% refund (remainder kept by contract)
     *  - After slot start → no cancellation allowed
     */
    function userCancelBooking(uint256 bookingId)
        external
        onlyRegistered
        bookingExists(bookingId)
    {
        Booking storage b = bookings[bookingId];
        require(b.bookedBy == msg.sender,         "CampusBooking: not your booking");
        require(b.status == BookingStatus.Active,  "CampusBooking: booking not active");
        require(block.timestamp < b.startTime,     "CampusBooking: slot already started");

        uint256 refund;
        if (block.timestamp + 24 hours <= b.startTime) {
            // More than 24 hours before → full refund
            refund = b.amountPaid;
        } else {
            // Within 24 hours → 50% refund
            refund = b.amountPaid / 2;
        }

        b.status       = BookingStatus.CancelledByUser;
        b.cancelledAt  = block.timestamp;
        b.refundAmount = refund;

        _sendRefund(msg.sender, refund);
        emit BookingCancelledByUser(bookingId, refund);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VIEW FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────────

    function getAsset(uint256 assetId) external view returns (Asset memory) {
        return assets[assetId];
    }

    function getAllAssetIds() external view returns (uint256[] memory) {
        return assetIds;
    }

    function getBooking(uint256 bookingId) external view returns (Booking memory) {
        return bookings[bookingId];
    }

    function getAllBookingIds() external view returns (uint256[] memory) {
        return bookingIds;
    }

    function getAssetBookings(uint256 assetId) external view returns (uint256[] memory) {
        return _assetBookings[assetId];
    }

    function getUserBookings(address user) external view returns (uint256[] memory) {
        return _userBookings[user];
    }

    function getRegisteredUsers() external view returns (address[] memory) {
        return registeredUserList;
    }

    /**
     * @notice Compute the required ETH for a booking (helper for frontend).
     */
    function computeFee(uint256 assetId, uint256 startTime, uint256 endTime)
        external view assetExists(assetId) returns (uint256 fee)
    {
        require(endTime > startTime, "end must be after start");
        uint256 hours_ = (endTime - startTime) / 3600;
        fee = hours_ * assets[assetId].hourlyFeeWei;
    }

    /**
     * @notice Check if a slot is available for an asset.
     */
    function isSlotAvailable(uint256 assetId, uint256 startTime, uint256 endTime)
        external view returns (bool)
    {
        uint256[] storage ids = _assetBookings[assetId];
        for (uint256 i = 0; i < ids.length; i++) {
            Booking storage b = bookings[ids[i]];
            if (b.status == BookingStatus.Active) {
                if (startTime < b.endTime && endTime > b.startTime) {
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * @notice Returns contract's accumulated ETH (penalty amounts from 50% refunds).
     */
    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Admin can withdraw penalty funds.
     */
    function withdrawPenalties() external onlyAdmin {
        uint256 bal = address(this).balance;
        require(bal > 0, "CampusBooking: nothing to withdraw");
        (bool ok, ) = admin.call{value: bal}("");
        require(ok, "CampusBooking: withdraw failed");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INTERNAL HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev Reverts if [startTime, endTime) overlaps any active booking for assetId.
     */
    function _rejectIfConflict(uint256 assetId, uint256 startTime, uint256 endTime) internal view {
        uint256[] storage ids = _assetBookings[assetId];
        for (uint256 i = 0; i < ids.length; i++) {
            Booking storage b = bookings[ids[i]];
            if (b.status == BookingStatus.Active) {
                // Overlap: new start < existing end AND new end > existing start
                if (startTime < b.endTime && endTime > b.startTime) {
                    revert("CampusBooking: slot conflict with existing booking");
                }
            }
        }
    }

    /**
     * @dev Sends ETH, reverts on failure.
     */
    function _sendRefund(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "CampusBooking: refund transfer failed");
    }

    // Accept plain ETH (not used in normal flow)
    receive() external payable {}
}
