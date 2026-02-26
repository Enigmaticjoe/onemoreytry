package com.aisherpa.app.data.api

import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

object ApiClient {

    private fun buildClient(): OkHttpClient {
        val logging = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BODY
        }
        return OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .addInterceptor(logging)
            .build()
    }

    fun createSherpaService(baseUrl: String): SherpaApiService {
        return Retrofit.Builder()
            .baseUrl(baseUrl.trimEnd('/') + "/")
            .client(buildClient())
            .addConverterFactory(GsonConverterFactory.create())
            .build()
            .create(SherpaApiService::class.java)
    }

    fun createKvmService(baseUrl: String): KvmApiService {
        return Retrofit.Builder()
            .baseUrl(baseUrl.trimEnd('/') + "/")
            .client(buildClient())
            .addConverterFactory(GsonConverterFactory.create())
            .build()
            .create(KvmApiService::class.java)
    }
}
