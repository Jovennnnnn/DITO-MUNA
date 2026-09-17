package com.example.myapplication

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.EditText
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.example.myapplication.models.ApiResponse
import com.example.myapplication.models.UserData
import com.example.myapplication.models.VerifyOtpRequest
import com.example.myapplication.network.RetrofitClient
import com.example.myapplication.utils.CustomNotification
import com.example.myapplication.utils.SessionManager
import com.google.gson.Gson
import retrofit2.Call
import retrofit2.Callback
import retrofit2.Response

class Verify2FAActivity : AppCompatActivity() {
    private lateinit var sessionManager: SessionManager
    private lateinit var userJson: String
    private lateinit var userData: UserData
    private lateinit var pbVerify: ProgressBar
    private lateinit var etOtp: EditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_verify_2fa)

        sessionManager = SessionManager(this)
        userJson = intent.getStringExtra("user_data") ?: ""
        userData = Gson().fromJson(userJson, UserData::class.java)

        pbVerify = findViewById(R.id.pb_verify)
        etOtp = findViewById(R.id.et_otp)

        findViewById<View>(R.id.btn_verify).setOnClickListener {
            verifyOtp()
        }

        findViewById<TextView>(R.id.tv_resend).setOnClickListener {
            resendOtp()
        }
    }

    private fun verifyOtp() {
        val otp = etOtp.text.toString().trim()
        if (otp.length != 6) {
            CustomNotification.showTopNotification(this, "Enter 6-digit code")
            return
        }

        showLoading(true)
        val request = VerifyOtpRequest(userData.email, otp)
        RetrofitClient.instance.verifyOtp(request).enqueue(object : Callback<ApiResponse> {
            override fun onResponse(call: Call<ApiResponse>, response: Response<ApiResponse>) {
                showLoading(false)
                if (response.isSuccessful && response.body()?.success == true) {
                    sessionManager.saveUser(userData)
                    CustomNotification.showTopNotification(this@Verify2FAActivity, "Verification Successful!", false)
                    Handler(Looper.getMainLooper()).postDelayed({
                        navigateToDashboard(userData.role)
                    }, 1000)
                } else {
                    CustomNotification.showTopNotification(this@Verify2FAActivity, response.body()?.message ?: "Invalid Code")
                }
            }

            override fun onFailure(call: Call<ApiResponse>, t: Throwable) {
                showLoading(false)
                CustomNotification.showTopNotification(this@Verify2FAActivity, "Error: ${t.message}")
            }
        })
    }

    private fun resendOtp() {
        // We reuse forgotPassword API to send a new OTP
        // but for a real 2FA we might have a specific send_2fa_otp.php
        CustomNotification.showTopNotification(this, "Sending new code...", false)
        // Implementation for resending...
    }

    private fun navigateToDashboard(role: String?) {
        val intent = when (role?.lowercase()) {
            "admin" -> Intent(this, AdminDashboardActivity::class.java)
            "resident" -> Intent(this, ResidentDashboardActivity::class.java)
            "driver" -> Intent(this, DriverDashboardActivity::class.java)
            else -> null
        }
        if (intent != null) {
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            startActivity(intent)
            finish()
        }
    }

    private fun showLoading(show: Boolean) {
        pbVerify.visibility = if (show) View.VISIBLE else View.GONE
        findViewById<View>(R.id.btn_verify).isEnabled = !show
    }
}