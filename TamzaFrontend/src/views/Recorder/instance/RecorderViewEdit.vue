<script setup lang="ts">
import App from '@/App.vue';
import { useRoute } from 'vue-router';

const route = useRoute();

</script>

<template>
  <h2>Recorder Edit</h2>
  <p>This is the edit recorder view.</p>
  <p>Editing recorder with ID: {{ route.params.id }}</p>
</template>

<style scoped lang="scss">
 
</style>
